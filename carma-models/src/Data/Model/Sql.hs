
{-# LANGUAGE ExistentialQuantification #-}

module Data.Model.Sql where

import Data.Typeable
import GHC.TypeLits

import Data.Model


mkSelectDictQuery
  :: (SingI name, Typeable model, SqlConstraint ctr)
  => (model -> Field name typ) -> ctr
  -> (String, ValueType ctr)
mkSelectDictQuery f ctr = (sql, sqlVal ctr)
  where
    sql = "SELECT id::text, " ++ fieldName f ++ "::text"
        ++ " FROM " ++ show (modelName f)
        ++ " WHERE " ++ sqlPart ctr


class SqlConstraint ctr where
  type ValueType ctr
  sqlPart :: ctr -> String
  sqlVal  :: ctr -> ValueType ctr

instance SqlConstraint () where
  type ValueType () = ()
  sqlPart _ = "true"
  sqlVal  _ = ()

instance (SqlConstraint c1, SqlConstraint c2) => SqlConstraint (c1, c2) where
  type ValueType (c1, c2) = (ValueType c1, ValueType c2)
  sqlPart (c1,c2) = sqlPart c1 ++ " AND " ++ sqlPart c2
  sqlVal  (c1,c2) = (sqlVal c1, sqlVal c2)


data SqlEq name typ model = SqlEq
  { eqc_field :: model -> Field name typ
  , eqc_val   :: typ
  }

instance (Typeable model, SingI name)
  => SqlConstraint (SqlEq name typ model)
  where
    type ValueType (SqlEq name typ model) = typ
    sqlPart c = fieldName (eqc_field c) ++ " = ?"
    sqlVal    = eqc_val
