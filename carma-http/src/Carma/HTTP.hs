{-# LANGUAGE OverloadedStrings #-}

{-|

  Interface to HTTP API for CRUD operations on model instances as
  provided by CaRMa server running on localhost.

-}

module Carma.HTTP
    ( FieldName
    , FieldValue
    , InstanceData
    , instanceRequest
    , createInstance
    , readInstance
    , updateInstance
    , deleteInstance
    , instanceExists
    )

where

import Data.Aeson
import Data.Functor
import Data.Map as M
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as B8
import qualified Data.ByteString.Lazy.Char8 as BSL

import Network.HTTP

import Carma.HTTP.Util


type FieldValue = BS.ByteString

type FieldName = BS.ByteString

-- | An instance of a model is a set of key-value pairs.
type InstanceData = M.Map FieldName FieldValue


-- | Model API endpoint.
modelURI :: Int
           -- ^ CaRMa port.
         -> String
         -- ^ Model name.
         -> String
modelURI cp model = concat ["http://localhost:", show cp, "/_/", model, "/"]


-- | Model read/update/delete API endpoint.
modelPidURI :: Int -> String -> Int -> String
modelPidURI cp model pid = (modelURI cp model) ++ (show pid)


-- | Send request to c/r/u/d an instance of model, possibly using new
-- instance data. Return id and instance data from server response.
instanceRequest :: Int
                -- ^ CaRMa port.
                -> String
                -- ^ Model name.
                -> Maybe Int
                -- ^ Model id.
                -> RequestMethod
                -> Maybe InstanceData
                -- ^ Request payload.
                -> IO (Int, Maybe InstanceData)
instanceRequest cp model rid rm row = do
  let uri =
          case rid of
            Just n  -> modelPidURI cp model n
            Nothing -> modelURI cp model
  rs <- simpleHTTP $
        case row of
          Just payload ->
              mkRequestWithBody uri rm $
              Just ("application/json", BSL.unpack $ encode payload)
          Nothing -> mkRequestWithBody uri rm Nothing
  inst <- (decode' . BSL.pack) <$> getResponseBody rs
  return $ case rid of
    -- We already know id
    Just n -> (n, inst)
    -- If no id provided, then we expect server to give us one
    Nothing ->
        -- Try to parse instance data from server response
        case inst of
          Just d -> case M.lookup "id" d of
                      Just carmaId ->
                          case B8.readInt carmaId of
                            Just (n, _) -> (n, Just d)
                            Nothing     ->
                                error "Could not read id from CaRMa response"
                      Nothing -> error "CaRMa response contains no id field"
          -- Fail if no id provided and could not read response
          Nothing -> error "Could not read CaRMa response"


-- | Wrapper for 'instanceRequest' which requires non-Nothing server
-- response.
requireValidResponse :: Monad m =>
                        (Int, Maybe InstanceData)
                     -> m (Int, InstanceData)
requireValidResponse (cid, rs) =
    case rs of
      Just d -> return (cid, d)
      Nothing -> error "No valid CaRMa response"


createInstance :: Int -> String -> InstanceData -> IO (Int, InstanceData)
createInstance cp model row =
    instanceRequest cp model Nothing POST (Just row)
                        >>= requireValidResponse


readInstance :: Int -> String -> Int -> IO InstanceData
readInstance cp model rid = 
    snd <$> (instanceRequest cp model (Just rid) GET Nothing 
                                 >>= requireValidResponse)


updateInstance :: Int -> String -> Int -> InstanceData -> IO InstanceData
updateInstance cp model rid row =
    snd <$> (instanceRequest cp model (Just rid) PUT (Just row) 
                        >>= requireValidResponse)


deleteInstance :: Int -> String -> Int -> IO ()
deleteInstance cp model rid =
    instanceRequest cp model (Just rid) DELETE Nothing >> return ()


-- | Check if instance exists in the CaRMa database.
instanceExists :: Int
               -- ^ CaRMa port.
               -> String
               -- ^ Model name.
               -> Int
               -- ^ Instance id.
               -> IO Bool
instanceExists cp modelName rid = do
  rs <- simpleHTTP $ getRequest $ modelPidURI cp modelName rid
  code <- getResponseCode rs
  return $
   case code of
     (2, 0, 0) -> True
     (4, 0, 4) -> False
     _ -> error "Unexpected CaRMa response"
