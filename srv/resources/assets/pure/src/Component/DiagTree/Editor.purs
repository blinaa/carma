module Component.DiagTree.Editor
     ( diagTreeEditor
     ) where

import Prelude hiding (div)

import Data.Array as A
import Data.Either (Either (..))
import Data.Maybe (Maybe (..), fromMaybe)

import Record.Builder (merge)

import Effect.Aff (launchAff_)

import Web.HTML (window) as DOM
import Web.HTML.Window (confirm) as DOM

import React
     ( ReactClass, component, createLeafElement, getProps
     )

import React.SyntheticEvent (preventDefault)
import React.DOM (div, div', p', span, button, i, i', ul', li', h5', text)
import React.DOM.Props (className, onClick, disabled, title)

import Utils ((<.>), storeConnect)

import Utils.CopyPasteBuffer
     ( CopyPasteBufferState (..)
     , CopyPasteBuffer
     , getCopyPasteState
     )

import Utils.DiagTree.Editor (getSlideByBranch)
import Component.Generic.Spinner (spinner)
import Component.DiagTree.Editor.Tree (diagTreeEditorTree)
import Component.DiagTree.Editor.TreeSearch (diagTreeEditorTreeSearch)
import Component.DiagTree.Editor.SlideEditor (diagTreeEditorSlideEditor)
import App.Store (Store, dispatch)
import App.Store.Reducers (AppState)
import App.Store.Actions (AppAction (DiagTree))
import App.Store.DiagTree.Actions (DiagTreeAction (Editor))

import App.Store.DiagTree.Editor.Types
     ( DiagTreeSlide (DiagTreeSlide)
     , DiagTreeSlides
     )

import App.Store.DiagTree.Editor.Actions
     ( DiagTreeEditorAction ( LoadSlidesRequest
                            , NewSlideRequest
                            , PasteSlideRequest
                            )
     )


diagTreeEditorRender
  :: ReactClass { store                     :: Store AppState AppAction
                , isSlidesLoading           :: Boolean
                , isSlidesLoaded            :: Boolean
                , isSlidesLoadingFailed     :: Boolean
                , isParsingSlidesDataFailed :: Boolean
                , isSlideDeletingFailed     :: Boolean
                , slideDeletingFailureSfx   :: Maybe String
                , isNewSlideFailed          :: Boolean
                , isProcessing              :: Boolean
                , isPasteFailed             :: Boolean
                , copyPasteBuffer           :: CopyPasteBuffer
                , slides                    :: DiagTreeSlides
                }

diagTreeEditorRender = defineComponent $
  \ { newSlide, pasteSlide, processingSpinnerProps }
    { store
    , isSlideDeletingFailed
    , slideDeletingFailureSfx
    , isNewSlideFailed
    , isProcessing
    , isPasteFailed
    , copyPasteBuffer
    } ->

  [ div
      [ className $ "col-md-4" <.> classSfx "tree-panel" ]
      [ div
          [ className "btn-toolbar" ]
          [ button
              [ className "btn btn-success"
              , disabled isProcessing
              , onClick newSlide
              ]
              [ i [className "glyphicon glyphicon-plus"] mempty
              , text " Новое дерево"
              ]

          , button
              [ className $ "btn" <.> classSfx "paste"
              , title "Вставить ветвь"
              , onClick pasteSlide

              , -- disabled if buffer contains root element or empty
                disabled
                  (  A.length (fromMaybe mempty copyPasteBuffer.branch) == 1
                  || getCopyPasteState copyPasteBuffer == EmptyBuffer
                  )
              ]
              [ i [className $ "glyphicon" <.> "glyphicon-paste"] mempty ]
          ]

      , treeSearchEl { store, isDisabled: isProcessing }

      , if not isProcessing
           then treeEl { store }
           else div [className $ classSfx "processing"]
                    [spinnerEl processingSpinnerProps]

      , -- A hint for a user
        div
          [ className $ classSfx "tree-hints" ]
          [ h5' $ pure $ text "Обозначения:"
          , ul'
              [ li' $ pure $ text "📂 — Раскрытая ветвь"
              , li' $ pure $ text "🏁 — Конец ветви (нет вложенных шагов)"
              ]
          ]
      ]

  , div
      [ className $ "col-md-8" <.> classSfx "slide-editor-panel" ] $
      ( if not isSlideDeletingFailed
           then mempty
           else pure $
                p' $
                  [ span [className "label label-danger"] [text "Ошибка"] ]
                  <>
                  let
                    sfx = slideDeletingFailureSfx
                    msg = " Произошла ошибка при попытке удалить ветвь"
                  in
                    case sfx of
                         Nothing -> pure $ text $ msg <> "."
                         Just x  -> [ text msg
                                    , i' $ pure $ text x
                                    , text "."
                                    ]
      )
      <>
      ( if not isNewSlideFailed
           then mempty
           else pure $
                p' [ span [className "label label-danger"] [text "Ошибка"]
                   , text " Произошла ошибка при попытке создать новое дерево."
                   ]
      )
      <>
      ( pure $
        if not isProcessing
           then slideEditorEl { store }
           else div [className $ classSfx "processing"]
                    [spinnerEl processingSpinnerProps]
      )
  ]

  where
    name = "DiagTreeEditor"
    classSfx s = name <> "--" <> s
    wrapper = div [className name]

    spinnerEl     = createLeafElement spinner
    treeSearchEl  = createLeafElement diagTreeEditorTreeSearch
    treeEl        = createLeafElement diagTreeEditorTree
    slideEditorEl = createLeafElement diagTreeEditorSlideEditor

    renderFn mainRender props = wrapper $ pure $
      div [className "container"] $ pure $
        div [className "row"] $
          branching mainRender props

    branching mainRender props
      | props.isSlidesLoadingFailed = pure $
          div' $ pure $
            p'
              [ span [className "label label-danger"] [text "Ошибка"]
              , text if props.isParsingSlidesDataFailed
                        then " Произошла ошибка при обработке\
                             \ полученных от сервера данных"
                        else " Произошла ошибка при загрузке данных"
              ]

      | props.isSlidesLoading = pure $
          div [className "text-center"] $ pure $
            spinnerEl
              { withLabel : Left true
              , store     : props.store
              }

      | props.isSlidesLoaded =
          mainRender props

      | otherwise = pure $
          div' $ pure $
            p' [ span [className "label label-warning"] $ pure $ text "Ожидание"
               , text " Данные ещё не загружены…"
               ]

    newSlideHandler store this event = do
      preventDefault event
      { isProcessing } <- getProps this

      if isProcessing
         then pure unit
         else do
           isSlideCreationConfirmed <-
             DOM.confirm "Подтвердите создание нового дерева" =<< DOM.window

           if not isSlideCreationConfirmed
              then pure unit
              else launchAff_
                 $ dispatch store
                 $ DiagTree $ Editor NewSlideRequest

    pasteSlideHandler store this event = do
      preventDefault event
      { isProcessing } <- getProps this
      getSlide <- getProps this <#> _.slides >>> getSlideByBranch
      copyPasteBuffer <- getProps this <#> _.copyPasteBuffer

      if isProcessing
         then pure unit
         else do
           isPasteToRootConfirmed <-
             let source = copyPasteBuffer.branch >>= getSlide <#> slideSfx

                 operation =
                   if copyPasteBuffer.cutting
                      then "переместить"
                      else "скопировать"

                 msg
                   =  "Вы уверены, что хотите "
                   <> operation
                   <> fromMaybe "" source
                   <> " в корень?"

              in DOM.window >>= DOM.confirm msg

           if not isPasteToRootConfirmed
              then pure unit
              else launchAff_
                 $ dispatch store
                 $ DiagTree $ Editor $ PasteSlideRequest mempty

    defineComponent mainRender = component name \this -> do
      { store } <- getProps this

      let preBound =
            { newSlide   : newSlideHandler   store this
            , pasteSlide : pasteSlideHandler store this
            , processingSpinnerProps: { withLabel: Right "Обработка…", store }
            }

      let r = renderFn $ mainRender preBound

      pure
        { render: r <$> getProps this

        , componentDidMount: do
            { isSlidesLoaded, isSlidesLoading } <- getProps this

            if isSlidesLoaded || isSlidesLoading
               then pure unit
               else launchAff_
                  $ dispatch store
                  $ DiagTree $ Editor LoadSlidesRequest
        }


diagTreeEditor :: ReactClass { store :: Store AppState AppAction }
diagTreeEditor = storeConnect f diagTreeEditorRender where
  f appState = merge let branch = appState.diagTree.editor in
    { isSlidesLoading           : branch.isSlidesLoading
    , isSlidesLoaded            : branch.isSlidesLoaded
    , isSlidesLoadingFailed     : branch.isSlidesLoadingFailed
    , isParsingSlidesDataFailed : branch.isParsingSlidesDataFailed
    , isNewSlideFailed          : branch.newSlide.isFailed
    , isPasteFailed             : branch.copyPasteBuffer.isFailed
    , isProcessing              : branch.slideDeleting.isProcessing
                                    || branch.newSlide.isProcessing
                                    || branch.copyPasteBuffer.isProcessing

    , isSlideDeletingFailed     : branch.slideDeleting.isFailed
    , slideDeletingFailureSfx   : getSlideDeletingFailureSfx branch
    , copyPasteBuffer           : branch.copyPasteBuffer
    , slides                    : branch.slides
    }

  getSlideDeletingFailureSfx branch = do
    deletingBranch <- branch.slideDeleting.branch
    getSlideByBranch branch.slides deletingBranch <#> slideSfx


slideSfx :: DiagTreeSlide -> String
slideSfx (DiagTreeSlide x) = " #" <> show x.id <> " (\"" <> x.header <> "\")"
