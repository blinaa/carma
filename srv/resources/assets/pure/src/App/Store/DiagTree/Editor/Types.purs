module App.Store.DiagTree.Editor.Types
     ( DiagTreeSlideId
     , DiagTreeSlides
     , DiagTreeSlide (DiagTreeSlide)
     , DiagTreeSlideResource
     , DiagTreeSlideAction
     , DiagTreeSlideAnswer
     ) where

import Data.Map (Map)
import Data.Maybe (Maybe)
import Data.DateTime (DateTime)


type DiagTreeSlideId = Int
type DiagTreeSlides  = Map DiagTreeSlideId DiagTreeSlide


type DiagTreeSlideResource =
  { text :: String
  , file :: String
  }


type DiagTreeSlideAction =
  { label   :: String
  , service :: String
  }


type DiagTreeSlideAnswer =
  { nextSlide :: DiagTreeSlide

  , header    :: String
  -- ^ Also known as "answer" of a slide
  --   (a user's answer that leads to this slide - `nextSlide`).

  , text      :: String
  , file      :: Maybe String
  }


-- `newtype` is required here to allow recursive types
newtype DiagTreeSlide
  = DiagTreeSlide
  { id        :: DiagTreeSlideId
  , isRoot    :: Boolean
  , ctime     :: DateTime
  , header    :: String -- ^ Also known as "question" of a slide
  , body      :: String
  , resources :: Array DiagTreeSlideResource
  , actions   :: Array DiagTreeSlideAction

  , answers   :: Map DiagTreeSlideId DiagTreeSlideAnswer
  -- ^ You could read "answers" here as "children slides"
  }
