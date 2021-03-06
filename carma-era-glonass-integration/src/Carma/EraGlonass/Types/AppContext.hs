{-# LANGUAGE ExplicitNamespaces, DataKinds #-}

module Carma.EraGlonass.Types.AppContext
     ( type AppContext   (..)
     , type AppMode      (..)
     , type DBConnection (..)
     ) where

import           Data.Pool (type Pool)
import           Data.Time.Clock (type UTCTime)

import           Control.Concurrent.STM.TQueue (type TQueue)
import           Control.Concurrent.STM.TMVar (type TMVar)
import           Control.Concurrent.STM.TVar (type TVar)
import           Control.Concurrent.STM.TSem (type TSem)

import           Database.Persist.Sql (type SqlBackend)

import           Servant.Client (type ClientEnv)

import           Carma.Monad.LoggerBus.Types (type LogMessage)

import           Carma.EraGlonass.Types.EGContractId (type EGContractId)
import           Carma.EraGlonass.Types.EGIntegrationPoint
                   ( type EGIntegrationPoint
                        ( BindVehicles
                        , ChangeProcessingStatus
                        )
                   )


-- | Application context which holds shared data.
data AppContext
   = AppContext
   { appMode :: AppMode
       -- ^ See @AppMode@ description for details.
       --
       -- This field placed to @AppContext@ for a situation where it have to be
       -- checked inside some route.

   , loggerBus :: TQueue LogMessage
       -- ^ A bus to send log messages to.

   , dbConnection :: DBConnection
       -- ^ A @Pool@ of connections to PostgreSQL or single connection.

   , dbRequestTimeout :: Int
       -- ^ Timeout in microseconds after which database request will fail.

   , backgroundTasksCounter :: TVar Word
       -- ^ Every big operation or an operation which affects DB data supposed
       --   to increment this counter and decrement it when it finishes.
       --
       -- For tests it helps to detect when everything is done at the moment.

   , egClientEnv :: ClientEnv
       -- ^ @ClientEnv@ with bound base URL for CaRMa -> Era Glonass requests.

   , vinSynchronizerIsEnabled :: Bool
       -- ^ Indicates whether VIN synchronizer is turned on.

   , vinSynchronizerTimeout :: Int
       -- ^ VIN synchronization iteration timeout in microseconds.
       --
       -- One iteration includes requests to EG side and own database requests.

   , vinSynchronizerRetryInterval :: Int
       -- ^ An interval (in microseconds) between next VIN synchronization
       --   attempt if previous one is failed.

   , vinSynchronizerBatchSize :: Word
       -- ^ A limit of how many VINs to synchronize per one request.

   , vinSynchronizerContractId :: EGContractId 'BindVehicles
       -- ^ Predefined on Era Glonass side code.

   , vinSynchronizerTriggerBus :: Maybe (TMVar UTCTime)
       -- ^ Useful to manually trigger VIN synchronization.
       --
       -- When it's empty it means VIN synchronizer is waiting for next
       -- scheduled launch or for next menual trigger.
       --
       -- When it's not empty it means VIN synchronization is in progress, after
       -- VIN Synchronizer is done and reached next iteration it will flush this
       -- bus, leaving it empty, starting to wait again for next manual trigger.
       --
       -- When you trigger it you put current time to this bus, so you could
       -- check the time of start of currently processing synchronization.
       --
       -- In case VIN synchronization is triggered by schedule, it will itself
       -- fill this bus with time of start of that synchronization (to notify
       -- others it's busy).
       --
       -- @Nothing@ when VIN synchronizer is not enabled.

   , statusSynchronizerIsEnabled :: Bool
       -- ^ Indicates whether status synchronizer is turned on.

   , statusSynchronizerInterval :: Int
       -- ^ An interval (in microseconds) between next statuses synchronization.

   , statusSynchronizerTimeout :: Int
       -- ^ Statuses synchronization iteration timeout in microseconds.
       --
       -- One iteration includes requests to EG side and own database requests.

   , statusSynchronizerContractId
       :: Maybe (EGContractId 'ChangeProcessingStatus)
       -- ^ Predefined on Era Glonass side code.

   , statusSynchronizerTriggerBus :: Maybe (TMVar UTCTime)
       -- ^ Useful to manually trigger statuses synchronization.
       --
       -- When it's empty it means Status Synchronizer is waiting for next
       -- scheduled launch or for next menual trigger.
       --
       -- When it's not empty it means statuses synchronization is in progress,
       -- after Status Synchronizer is done and reached next iteration it will
       -- flush this bus, leaving it empty, starting to wait again for next
       -- manual trigger.
       --
       -- When you trigger it you put current time to this bus, so you could
       -- check the time of start of currently processing synchronization.
       --
       -- In case statuses synchronization is triggered after regular interval,
       -- it will itself fill this bus with time of start of that
       -- synchronization (to notify others it's busy).
       --
       -- @Nothing@ when Status Synchronizer is not enabled.
   }


-- | Application mode that indicates whether it's either production mode that
--   connects to PostgreSQL database or testing mode with SQLite in-memory
--   database.
data AppMode
   = ProductionAppMode
   | TestingAppMode
     deriving (Show, Eq)


-- | A container to bring database connection to route handlers.
data DBConnection
   -- | In-memory SQLite database cannot have @Pool@.
   = DBConnection TSem SqlBackend
   | DBConnectionPool (Pool SqlBackend)
