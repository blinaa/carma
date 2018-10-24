{-# LANGUAGE GADTs, GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses, TypeFamilies #-}
{-# LANGUAGE QuasiQuotes, TemplateHaskell #-}
{-# LANGUAGE FlexibleInstances #-}

module Carma.EraGlonass.Model.EraGlonassSynchronizedContract.Persistent where

import           Data.Typeable
import           Data.Time.Clock
import           Data.Text

import           Database.Persist.TH

import           Carma.Model.Contract.Persistent (ContractId)


-- | @EraGlonassSynchronizedContract@ persistent model.
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
EraGlonassSynchronizedContract json sql=EraGlonassSynchronizedContract
  ctime UTCTime sql=ctime default=CURRENT_TIME
  contract ContractId sql=contractid

  vin Text sql=vin -- ^ VIN which have been used to synchronize a @Contract@.
                   -- Could be useful for debugging in case some @Contract@'s
                   -- data have been changed after a synchronization.

  isSynchronized Bool sql=issynchronized
  lastStatusChangeTime UTCTime Maybe sql=laststatuschangetime

  deriving Typeable Show
|]
