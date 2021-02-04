{-# LANGUAGE NoImplicitPrelude #-}

{-| Handler helpers. -}

module AppHandlers.Util where

import BasicPrelude

import Control.Monad.State.Class
import Data.Aeson as Aeson
import qualified Data.ByteString.Char8 as B
import qualified Data.Map as Map
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Data.Time (Day)
import Data.Time.Format (defaultTimeLocale, parseTimeM)

import Snap
import Util


writeJSON :: Aeson.ToJSON v => v -> Handler a b ()
writeJSON v = do
  modifyResponse $ setContentType "application/json"
  writeLBS $ Aeson.encode v


getJSONBody :: Aeson.FromJSON v => Handler a b v
getJSONBody = Util.readJSONfromLBS <$> readRequestBody (4 * 1024 * 1024)


handleError :: MonadSnap m => Int -> m ()
handleError err = do
    modifyResponse $ setResponseCode err
    getResponse >>= finishWith


quote :: ByteString -> String
quote x = "'" ++ (T.unpack $ T.replace "'" "''" $ T.decodeUtf8 x) ++ "'"


mkMap :: [Text] -> [[Maybe Text]] -> [Map Text Text]
mkMap fields = map $ Map.fromList . zip fields . map (fromMaybe "")


getParamT :: ByteString -> Handler a b (Maybe Text)
getParamT = fmap (fmap T.decodeUtf8) . getParam

getParamDate :: ByteString -> Handler a b (Maybe Day)
getParamDate p =
  getParam p >>= \v ->
      return $ case v of
                 Just d -> parseTimeM False defaultTimeLocale "%Y-%m-%d" $
                          B.unpack d
                 _      -> Nothing


getIntParam :: ByteString -> Handler a b (Maybe Int)
getIntParam name = do
  val <- getParam name
  return $ fst <$> (B.readInt =<< val)


withLens :: MonadState s (Handler b v')
         => (s -> SnapletLens b v) -> Handler b v res
         -> Handler b v' res
withLens x = (gets x >>=) . flip withTop
