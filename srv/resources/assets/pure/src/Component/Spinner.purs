module Component.Spinner
     ( spinner
     ) where

import Prelude hiding (div)

import React (ReactClass)
import React.DOM (div', div, text)
import React.DOM.Props (className)

import Utils (StoreConnectEff, createClassStatelessWithSpec)
import App.Store (AppContext)


spinnerRender
  :: forall eff
   . ReactClass { appContext :: AppContext (StoreConnectEff eff) }

spinnerRender = createClassStatelessWithSpec specMiddleware $ const $ div
  [ className "circle-spinner--with-label" ]
  [ div' [ text $ "Загрузка…" ]
  , div [ className "circle-spinner--icon" ] []
  ]

  where
    specMiddleware = _
      { shouldComponentUpdate = \_ _ _ -> pure false
      }


spinner
  :: forall eff
   . ReactClass { appContext :: AppContext (StoreConnectEff eff) }

spinner = spinnerRender