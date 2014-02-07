
{-# LANGUAGE QuasiQuotes,
             TemplateHaskell,
             ScopedTypeVariables,
             DeriveGeneric,
             TypeOperators,
             FlexibleInstances,
             FlexibleContexts,
             OverlappingInstances,
             UndecidableInstances
 #-}

module Snaplet.Search (Search, searchInit)  where

import           Prelude hiding (pred)
import           Control.Applicative ((<$>), (<*>))
import           Control.Monad
import           Control.Monad.State
import           Control.Lens (makeLenses)

import qualified Data.Map as M
import           Data.Monoid
import           Data.Maybe
import           Data.Either
import           Data.String (fromString)
import           Data.Pool
import           Data.Text (Text, toLower)
import qualified Data.Text             as T
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy  as LB
import qualified Data.HashMap.Strict   as HM
import           Text.Printf

import           Data.Aeson

import           Snap.Core
import           Snap.Snaplet
import           Snap.Snaplet.Auth hiding (Role)
import           Database.PostgreSQL.Simple as PG
import           Database.PostgreSQL.Simple.SqlQQ
import           Database.PostgreSQL.Simple.Types ((:.))

import           GHC.Generics

import           Util
import           Utils.HttpErrors

import qualified Data.Model       as M
import qualified Data.Model.Types as M

import           Data.Model.Patch

import           Carma.Model
import           Carma.Model.Role
import           Carma.Model.Case
import           Carma.Model.Service
import           Carma.Model.Service.Towage
import           Carma.Model.Search
import           Carma.Model.FieldPermission


data Search b = Search
  {postgres :: Pool Connection
  ,_auth    :: Snaplet (AuthManager b)
  }

makeLenses ''Search

type SearchHandler b t = Handler b (Search b) t


data SearchReq = SearchReq { predicates :: Value
                           , sorts      :: SearchSorts
                           } deriving (Show, Generic)

instance FromJSON SearchReq

data SearchSorts = SearchSorts { fields :: [SimpleField]
                               , order  :: Text
                               } deriving (Show, Generic)

instance FromJSON SearchSorts

data SimpleField = SimpleField { name :: Text, model :: Text }
                 deriving (Show, Generic)

instance FromJSON SimpleField

data SearchResult t = SearchResult 
  { values :: [t]
  , limit  :: Int
  , offset :: Int
  } deriving (Generic)
instance ToJSON t => ToJSON (SearchResult t)


instance forall m.(Model m) => ToJSON (Patch m :. ()) where
  toJSON (p :. ()) =
    object [(M.modelName (M.modelInfo :: M.ModelInfo m)) .= toJSON p]

instance forall m b.(Model m, ToJSON b) => ToJSON (Patch m :. b) where
  toJSON (p :. ps) = merge
    (object [(M.modelName (M.modelInfo :: M.ModelInfo m)) .= toJSON p])
    (toJSON ps)
    where
      merge :: Value -> Value -> Value
      merge (Object o1) (Object o2) =
        Object $ HM.fromList $ (HM.toList o1) ++ (HM.toList o2)


class StripRead p where
  stripRead :: Connection -> [IdentI Role] -> p -> IO p

instance (Model m, Model (M.Parent m)) => StripRead (Patch m) where
  stripRead = stripReadPatch
instance (Model m, Model (M.Parent m)) => StripRead (Patch m :. ()) where
  stripRead c rs (p :. ()) = stripReadPatch c rs p *:. ()
instance (Model m, Model (M.Parent m), StripRead ps)
         => StripRead (Patch m :. ps) where
  stripRead c rs (p :. ps) = stripReadPatch c rs p *:* stripRead c rs ps

(*:*) :: Monad m => m a -> m b -> m (a :. b)
(*:*) a b = do { a' <- a; b' <- b; return $ a' :. b' }

(*:.) :: Monad m => m a -> b -> m (a :. b)
(*:.) a b = do { a' <- a; return $ a' :. b }


caseSearch :: SearchHandler b (Either String Value)
caseSearch = do
  Just usr <- with auth currentUser
  let Just uid = userId usr
  lim      <- getLimit
  offset   <- getOffset
  args     <- getJsonBody
  let fs = fields $ sorts args
  withPG $ \c -> do
    casePreds  <- predicatesFromParams c (predicates args) caseSearchParams
    srvPreds   <- predicatesFromParams c (predicates args) serviceSearchParams
    towPreds   <- predicatesFromParams c (predicates args) towageSearchParams
    case partitionEithers [casePreds, srvPreds, towPreds] of
      ([], preds) -> do
        s  <- query_ c (mkQuery (concatPredStrings preds) 1 offset "")
        s' <- mapM (parsePatch c []) s
        return $ Right $ toJSON $ SearchResult s' lim offset
      (errs, _) -> return $ Left $ foldl (++) "" errs
  where
    parsePatch conn [] [c, s, t] = stripRead conn [] $
      (parse c :: Patch Case)    :.
      (parse s :: Patch Service) :.
      (parse t :: Patch Towage)  :.
      ()
    parse :: Model m => Maybe LB.ByteString -> Patch m
    parse (Just v) = parsePgJson v
    parse Nothing  = empty


parsePgJson :: forall m.Model m => LB.ByteString -> Patch m
parsePgJson bs =
  fromMaybe empty $ decode bs >>= decodeJs >>= fromResult . fromJSON
  where
    fromResult (Error s)   = Nothing
    fromResult (Success r) = Just r
    decodeJs (Object obj) =
      Just $ Object $ HM.foldlWithKey' fixName HM.empty obj
    decodeJs _ = Nothing
    fsMap    = M.modelFieldsMap (M.modelInfo :: M.ModelInfo m)
    namesMap =
      foldl (\a k -> HM.insert (toLower k) k a) HM.empty $ HM.keys fsMap
    fixName h k v = maybe h (\f -> HM.insert f v h) $ HM.lookup k namesMap


search :: SearchHandler b (Either String Value) -> SearchHandler b ()
search = (>>= either (finishWithError 500) writeJSON)


mkQuery :: Text -> Int -> Int -> Text -> Query
mkQuery pred lim offset ord
  = fromString $ printf
      (  "    select row_to_json(casetbl.*)    :: text,"
      ++ "           row_to_json(servicetbl.*) :: text,"
      ++ "           row_to_json(towagetbl.*)  :: text"
      ++ "     from casetbl left join servicetbl"
      ++ "       on split_part(servicetbl.parentId, ':', 2)::int = casetbl.id"
      ++ "     left join towagetbl"
      ++ "       on servicetbl.id = towagetbl.id"
      ++ "     where (%s) %s limit %i offset %i;"
      )
      (T.unpack pred)  (T.unpack ord) lim offset


searchInit
  :: Pool Connection -> Snaplet (AuthManager b) -> SnapletInit b (Search b)
searchInit conn sessionMgr = makeSnaplet "search" "Search snaplet" Nothing $ do
  addRoutes [("services", method POST $ search caseSearch)]
  return $ Search conn sessionMgr


-- Utils
----------------------------------------------------------------------
withPG :: (Connection -> IO a) -> SearchHandler b a
withPG f = gets postgres >>= liftIO . (`withResource` f)

getJsonBody :: FromJSON v => SearchHandler b v
getJsonBody = Util.readJSONfromLBS <$> readRequestBody 4096

getLimit :: SearchHandler b Int
getLimit
  = fromMaybe 10 . (>>= fmap fst . B.readInt)
  <$> getParam "limit"

getOffset :: SearchHandler b Int
getOffset
  = fromMaybe 0 . (>>= fmap fst . B.readInt)
  <$> getParam "offset"

writeJSON :: ToJSON v => v -> Handler a b ()
writeJSON v = do
  modifyResponse $ setContentType "application/json"
  writeLBS $ encode v
