{-# LANGUAGE ScopedTypeVariables #-}
module Snaplet.DbLayer.Triggers.Dsl where 

import Control.Applicative
import Control.Monad (when)
import Control.Monad.Trans (liftIO)
import qualified Control.Monad.State as ST

import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as B
import qualified Data.Text as T
import qualified Data.Text.Encoding as T

import Data.Time.Clock (getCurrentTime)
import Data.Time.Clock.POSIX (POSIXTime, utcTimeToPOSIXSeconds)

import Data.Map (Map)
import qualified Data.Map as Map
import Data.Maybe

import Snap.Snaplet.Auth
import Snaplet.Auth.Class
import Snaplet.DbLayer.Types
import Snaplet.DbLayer.Triggers.Types


tryAll :: Alternative f => (a -> f b) -> [a] -> f b
tryAll f = foldl (<|>) empty . map f

get :: MonadTrigger m b => ObjectId -> FieldName -> m b FieldValue
get objId field = do
  TriggerContext{..} <- ST.get
  let objs = mapMaybe (Map.lookup objId) [current, updates, dbCache]
  case tryAll (Map.lookup field) objs of
    Just val -> return val
    Nothing
      | Map.member objId dbCache -> return ""
      | otherwise -> do
        obj <- readObject objId
        ST.modify $ \st -> st{dbCache = Map.insert objId obj dbCache}
        return $ fromMaybe "" $ Map.lookup field obj


set :: MonadTrigger m b => ObjectId -> FieldName -> FieldValue -> m b ()
set objId field val = do
  val' <- get objId field
  when (val /= val') $ ST.modify $ \st ->
    st{current = Map.insertWith' Map.union objId
      (Map.singleton field val)
      $ current st
      }


setAll :: MonadTrigger m b => ObjectId -> Map FieldName FieldValue -> m b ()
setAll objId = mapM_ (uncurry $ set objId) . Map.toList


upd :: MonadTrigger m b => ObjectId -> FieldName -> (FieldValue -> FieldValue) -> m b ()
upd objId field fn = get objId field >>= set objId field . fn


new :: MonadTrigger m b => ModelName -> Object -> m b ObjectId
new model obj = do
  ct <- liftIO $ (round :: POSIXTime -> Int) . utcTimeToPOSIXSeconds
        <$> getCurrentTime
  let obj' = Map.insert "ctime" (B.pack $ show ct) obj
  intId <- createObject model obj'
  let objId = B.concat [model, ":", intId]
  let obj''  = Map.insert "id" intId obj'
  ST.modify $ \st -> st{current = Map.insert objId obj'' $ current st}
  return objId


addToList :: FieldValue -> FieldValue -> FieldValue
addToList val = B.intercalate "," . (val:) . filter (/=val) . B.split ','

dropFromList :: FieldValue -> FieldValue -> FieldValue
dropFromList val = B.intercalate "," . filter (/=val) . B.split ','

utf8 :: String -> ByteString
utf8 = T.encodeUtf8 . T.pack

getCurrentUser :: (MonadTrigger m b, HasAuth b) => m b (Maybe AuthUser)
getCurrentUser = liftDb (withAuth $ currentUser)

future :: MonadTrigger m b => DbHandler b () -> m b ()
future f = ST.modify $ \st -> st {futures = f : futures st}
