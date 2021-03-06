{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Data.Model.Patch
  ( Patch(Patch), untypedPatch
  , parentField
  , toParentIdent
  , toParentPatch
  , mergeParentPatch
  , IPatch
  , FullPatch, Data.Model.Patch.Object
  , get, get', put, delete, union, differenceFrom, singleton
  , empty
  , W(..)
  )

where

import Prelude hiding (null)

import Control.Applicative ((<|>))
import Control.Monad.Trans.Reader (ask)
import Control.Monad (mplus, replicateM_)
import Control.Monad.Trans.Class (lift)

import Data.ByteString (ByteString)
import Data.Maybe (catMaybes, fromMaybe)
import Data.Aeson.Types as Aeson
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HashMap
import Data.Text (Text, toLower, unpack)
import Data.Text.Encoding (decodeUtf8)
import Data.Text.Unsafe (unsafeDupablePerformIO)
import qualified Database.PostgreSQL.LibPQ as PQ
import Database.PostgreSQL.Simple.Internal ( Row(..)
                                           , RowParser(..)
                                           , conversionError)
import Database.PostgreSQL.Simple.FromField (ResultError(..))
import Database.PostgreSQL.Simple.FromRow
import Database.PostgreSQL.Simple.ToRow
import Database.PostgreSQL.Simple.Types

import Data.Dynamic

import Data.Singletons

import Data.Model


data Patch m -- FIXME: why HashMap, not good old Data.Map?
  = Patch { untypedPatch :: HashMap Text Dynamic }
  deriving Typeable


-- | A version of 'Patch' guaranteed to have all fields.
newtype FullPatch m =
  FullPatch (Patch m) deriving (IPatch, ToJSON, ToRow, Typeable)


type Object m = FullPatch m


class IPatch p where
  -- | Add a field to a patch.
  put :: (Typeable t, SingI name) =>
         (m -> Field t (FOpt name desc app)) -> t -> p m -> p m

  -- | Delete a field from a patch.
  delete :: (SingI name) =>
            (m -> Field t (FOpt name desc app)) -> p m -> Patch m


empty :: Patch m
empty = Patch HashMap.empty


instance IPatch Patch where
  put f v (Patch m) = Patch $ HashMap.insert (fieldName f) (toDyn v) m

  delete f (Patch m) = Patch $ HashMap.delete (fieldName f) m


get :: (Typeable t, SingI name) =>
       Patch m -> (m -> Field t (FOpt name desc app)) -> Maybe t
get (Patch m) f = (`fromDyn` (error "Dynamic error in patch")) <$>
                  HashMap.lookup (fieldName f) m


-- | Type-safe total version of 'get'.
get' :: (Typeable t, SingI name) =>
        FullPatch m -> (m -> Field t (FOpt name desc app)) -> t
get' (FullPatch p) f
  = fromMaybe (error $ "Patch field " ++ unpack (fieldName f) ++ " missing") $
    get p f


union :: Patch m -> Patch m -> Patch m
union p1 p2 = Patch $ HashMap.union (untypedPatch p1) (untypedPatch p2)


singleton :: (Typeable t, SingI name)
          => (m -> Field t (FOpt name desc app)) -> t -> Patch m
singleton f v = put f v empty


-- | Delete key-value pairs from the first argument if they exist in
-- the second. If only values differ for a key, the value from the
-- first argument is used.
differenceFrom :: forall m. Model m => Patch m -> Patch m -> Patch m
differenceFrom p1 p2 =
  Patch p
  where
    p1' = untypedPatch p1
    p2' = untypedPatch p2
    newKeys = HashMap.difference p1' p2'

    -- Filter intersection, leaving only fields with changed JSON
    -- values
    fields = modelFieldsMap (modelInfo :: ModelInfo m)
    toJS k = fd_toJSON $ fields HashMap.! k
    newVals =
      HashMap.filterWithKey
      (\k v -> (Just $ toJS k v) /= (toJS k <$> HashMap.lookup k p2')) $
      HashMap.intersection p1' p2'

    p = HashMap.union newKeys newVals


parentField :: Model m =>
               (Parent m -> Field t (FOpt name desc app))
            -> (m -> Field t (FOpt name desc app))
parentField _ _ = Field


toParentIdent
  :: Model m
  => Ident t m -> Ident t (Parent m)
toParentIdent = Ident . identVal


toParentPatch
  :: Model m
  => Patch m -> Patch (Parent m)
toParentPatch = Patch . untypedPatch


mergeParentPatch
  :: forall m . Model m
  => Patch m -> Patch (Parent m) -> Patch m
mergeParentPatch a b = case parentInfo :: ParentInfo m of
  NoParent   -> a
  ExParent p ->
    let ua = untypedPatch a
        ub = untypedPatch b
        fs = modelFieldsMap p
        ub'= HashMap.filterWithKey (\k _ -> HashMap.member k fs) ub
    in Patch $ HashMap.union ub' ua


instance Model m => FromJSON (Patch m) where
  parseJSON (Aeson.Object o)
    = Patch . HashMap.fromList
    <$> mapM parseField' (HashMap.toList o)
    where
      fields = modelFieldsMap (modelInfo :: ModelInfo m)
      parseField' (name, val) = case HashMap.lookup name fields of
        Nothing -> fail $ "Unexpected field: " ++ show name
        Just p  -> (name,) <$> fd_parseJSON p val
  parseJSON j = fail $ "JSON object expected but here is what I have: " ++ show j


instance Model m => ToJSON (Patch m) where
  toJSON (Patch m) = object [(k, toJS k v) | (k,v) <- HashMap.toList m]
    where
      fields = modelFieldsMap (modelInfo :: ModelInfo m)
      toJS k = fd_toJSON $ fields HashMap.! k


instance forall m b.(Model m, ToJSON b) => ToJSON (Patch m :. b) where
  toJSON (p :. ps) = merge
    (object [(modelName (modelInfo :: ModelInfo m)) .= toJSON p])
    (toJSON ps)
    where
      merge :: Value -> Value -> Value
      merge (Object o1) (Object o2) =
        Object $ HashMap.fromList $ (HashMap.toList o1) ++ (HashMap.toList o2)
      merge v1@(Object _) v2 | v2 == toJSON () = v1
                             | otherwise       = error "toJSON: bad pattern"
      merge _ _ = error "toJSON: bad pattern"


instance forall m b.(Model m, ToJSON b) => ToJSON (Maybe (Patch m) :. b) where
  toJSON (Just p :. ps)  = toJSON (p :. ps)
  toJSON (Nothing :. ps) = toJSON ps


instance Model m => FromRow (Patch m) where
  fromRow = Patch . HashMap.fromList <$> sequence
    [ (fd_name f,) <$> fd_fromField f
    | f <- onlyDefaultFields $ modelFields (modelInfo :: ModelInfo m)
    ]

instance Model m => ToRow (Patch m) where
  toRow (Patch m) = concatMap fieldToRow $ HashMap.toList m
    where
      -- NB. Please note that field order is significant
      -- it MUST match with the one in Patch.Sql.insert
      fields = modelFieldsMap (modelInfo :: ModelInfo m)
      fieldToRow (nm, val) = case HashMap.lookup nm fields of
        Just f@(FieldDesc{}) -> [fd_toField f val]
        Just _  -> [] -- skip ephemeral field
        Nothing -> [] -- skip unknown fields to allow upcasting child models

newtype W m = W { unW :: m }

-- | Special instance which can build patch retrieving fields by their names
instance Model m => FromRow (W (Patch m)) where
  fromRow = do
    n  <- numFieldsRemaining
    fs <- map decodeUtf8 <$> catMaybes <$> mapM fname [0..n-1]
    case filter (\(_, f) -> not $ hasField f) $ zip fs $ fields fs of
      [] -> W . Patch . HashMap.fromList <$> sequence
            [(fd_name f,) <$> fd_fromField f | f <- catMaybes $ fields fs]
      errs -> RP $ lift $ lift $ conversionError $
              ConversionFailed  "" Nothing "" "" $
        "Can't find this fields in model: " ++ (show $ map fst errs)
    where
      fM = modelFieldsMap (modelInfo :: ModelInfo m)
      fm = HashMap.foldl'
           (\a f -> HashMap.insert (toLower $ fd_name f) f a) HashMap.empty fM
      fields = map (\n -> HashMap.lookup n fM `mplus` HashMap.lookup n fm)
      hasField (Just _) = True
      hasField Nothing  = False

fname :: Int -> RowParser (Maybe ByteString)
fname n = RP $ do
  Row{..} <- ask
  return $ unsafeDupablePerformIO $ PQ.fname rowresult (PQ.toColumn n)

instance Model m => ToJSON (W (Patch m)) where
  toJSON (W p) = toJSON p


instance Model m => FromRow (FullPatch m) where
  fromRow = do
    let rowP :: RowParser (W (Patch m))
        rowP = fromRow
    p <- rowP
    return $ FullPatch $ unW p

null :: RowParser Null
null =  field

instance Model m => FromRow (Maybe (Patch m)) where
  fromRow =
    (replicateM_ n null *> pure Nothing) <|> (Just <$> fromRow)
    where
      n = length $ modelFields (modelInfo :: ModelInfo m)
