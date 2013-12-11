{-# LANGUAGE QuasiQuotes, TemplateHaskell, ScopedTypeVariables #-}

module Snaplet.Search (Search, searchInit)  where

import Prelude hiding (pred)
import Control.Applicative
import Control.Monad
import Control.Monad.State
import Control.Lens hiding (from)

import qualified Data.Map as M
import Data.Monoid
import Data.Maybe
import Data.Either
import Data.String (fromString)
import Data.Pool
import Data.Text (Text)
import qualified Data.Text             as T
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy as LB
import Text.Printf

import qualified Data.Aeson as Aeson

import Snap.Core
import Snap.Snaplet
import Snap.Snaplet.Auth
import Database.PostgreSQL.Simple as PG
import Database.PostgreSQL.Simple.SqlQQ

import Util
import Utils.HttpErrors

import Carma.Model.Case
import Carma.Model.Service
import Carma.Model.Service.Towage
import Carma.Model.Search

data Search b = Search
  {postgres :: Pool Connection
  ,_auth    :: Snaplet (AuthManager b)
  }
makeLenses ''Search

type SearchHandler b t = Handler b (Search b) t

modelFields :: UserId -> Text -> PG.Connection -> IO [Text]
modelFields uid modelName c
  = concat <$> query c q (modelName, unUid uid)
  where
    q = [sql|
      with
        model_name as (select (? || 'tbl')::text as table),
        usr_role as
          (select unnest(roles) as role from usermetatbl where uid = ?),
        svc_field as
          (select column_name as column
            from information_schema.columns, model_name
            where table_name = model_name.table),
        svc_model as
          (select c1.relname as table
            from pg_inherits p, pg_class c1, pg_class c2, model_name
            where p.inhrelid = c1.oid
              and p.inhparent = c2.oid
              and c2.relname = model_name.table)
        select distinct field
          from "FieldPermission" p, svc_field f, usr_role r,
            (select * from svc_model union select * from model_name) m
          where (model || 'tbl') = m.table
            and field ilike f.column
            and p.role = r.role :: int
            and p.r
      |]


caseSearch :: SearchHandler b (Either String Aeson.Value)
caseSearch = do
  Just usr <- with auth currentUser
  let Just uid = userId usr
  lim      <- getLimit
  offset   <- getOffset
  args     <- getJsonBody
  withPG $ \c -> do
    cse_fields <- modelFields uid "case" c
    svc_fields <- modelFields uid "service" c
    tow_fields <- modelFields uid "towage" c
    casePreds  <- predicatesFromParams c args caseSearchParams
    srvPreds   <- predicatesFromParams c args serviceSearchParams
    towPreds   <- predicatesFromParams c args towageSearchParams
    case partitionEithers [casePreds, srvPreds, towPreds] of
      ([], preds) -> do
        s :: [[LB.ByteString]] <-
          query_ c (mkQuery cse_fields svc_fields tow_fields
                    (concatPredStrings preds) lim offset)
        return $ return . reply lim offset =<<
          (sequence $ map (Aeson.eitherDecode . head) s)
      (errs, _) -> return $ Left $ foldl (++) "" errs
        -- -> Right . join
        --    <$> query_ c (mkQuery cse_fields svc_fields pred lim)

search :: SearchHandler b (Either String Aeson.Value) -> SearchHandler b ()
search = (>>= either (finishWithError 500) writeJSON)


mkQuery
   :: [Text] -> [Text] -> [Text] -> Text -> Int -> Int
   -> Query
mkQuery caseProj svcProj towProj pred lim offset
  = fromString $ printf ("with"
      ++ " result(cid,styp,sid) as"
      ++ "   (select casetbl.id, servicetbl.type, servicetbl.id"
      ++ "     from casetbl join servicetbl"
      ++ "       on split_part(servicetbl.parentId, ':', 2)::int = casetbl.id"
      ++ "     join towagetbl"
      ++ "       on servicetbl.id = towagetbl.id"
      ++ "     where (%s)),"
      ++ " json_result as"
      ++ "   (select"
      ++ "     row_to_json(c.*) as \"case\","
      ++ "     row_to_json(s.*) as \"service\","
      ++ "     row_to_json(t.*) as \"towage\""
      ++ "     from result r,"
      ++ "       (select %s from casetbl) as c,"
      ++ "       (select %s from servicetbl) as s,"
      ++ "       (select %s from towagetbl) as t"
      ++ "     where c.id = r.cid"
      ++ "       and s.id = r.sid and s.type = r.styp"
      ++ "       and s.id = t.id)"
      ++ " select row_to_json(r) :: text from json_result r limit %i offset %i;")
    (T.unpack pred)
    (T.unpack $ T.intercalate ", " $ map mkProj caseProj)
    (T.unpack $ T.intercalate ", " $ map mkProj svcProj)
    (T.unpack $ T.intercalate ", " $ map mkProj towProj)
    lim offset
  where
    mkProj f = T.concat [f, " as \"", f, "\""]


searchInit
  :: Pool Connection -> Snaplet (AuthManager b) -> SnapletInit b (Search b)
searchInit conn sessionMgr = makeSnaplet "search" "Search snaplet" Nothing $ do
  addRoutes [("services", method POST $ search caseSearch)]
  return $ Search conn sessionMgr

reply :: Int -> Int -> [Aeson.Value] -> Aeson.Value
reply lim offset val =
  let next = if length val < lim then Nothing else Just (offset + lim)
      prev = if offset <= 0      then Nothing else Just (offset - lim)
  in Aeson.object [ ("values", Aeson.toJSON val)
                  , ("next", Aeson.toJSON next)
                  , ("prev", Aeson.toJSON prev)
                  ]


-- Utils
----------------------------------------------------------------------
withPG :: (Connection -> IO a) -> SearchHandler b a
withPG f = gets postgres >>= liftIO . (`withResource` f)

getJsonBody :: SearchHandler b Aeson.Value
getJsonBody = Util.readJSONfromLBS <$> readRequestBody 4096

getLimit :: SearchHandler b Int
getLimit
  = fromMaybe 10 . (>>= fmap fst . B.readInt)
  <$> getParam "limit"

getOffset :: SearchHandler b Int
getOffset
  = fromMaybe 0 . (>>= fmap fst . B.readInt)
  <$> getParam "offset"

writeJSON :: Aeson.ToJSON v => v -> Handler a b ()
writeJSON v = do
  modifyResponse $ setContentType "application/json"
  writeLBS $ Aeson.encode v
