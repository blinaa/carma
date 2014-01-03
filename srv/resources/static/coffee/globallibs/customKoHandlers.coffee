ko.bindingHandlers.setdata =
  init: (element, valueAccessor, allBindingsAccessor, viewModel) ->
    # This will be called when the binding is first applied to an element
    # Set up any initial state, event handlers, etc. here
    $(element).data({ knockVM: viewModel, acc: valueAccessor})

ko.bindingHandlers.bindClick =
  init: (element, valueAccessor, allBindingsAccessor, viewModel) ->
    fn = valueAccessor()
    $(element).click ->
      fn(element, viewModel)

ko.bindingHandlers.updMultiDict =
  init: (element, valueAccessor, allBindingsAccessor, kvm) ->
    fn = valueAccessor()

ko.bindingHandlers.disabled =
  update: (el, acc, allBindigns, kvm) ->
    $(el).attr('disabled', acc()())

ko.bindingHandlers.readonly =
  update: (el, acc, allBindigns, kvm) ->
    $(el).attr('readonly', acc()())

ko.bindingHandlers.sync =
  update: (el, acc, allBindings) ->
    isSync = ko.utils.unwrapObservable acc()
    if isSync
      $(el).fadeIn 'fast'
    else
      $(el).fadeOut 'slow'

ko.bindingHandlers.spinner =
  update: (el, acc, allBindings) ->
    showSpinner = ko.utils.unwrapObservable acc()
    if showSpinner
      $(el).children(':not(.spinner)').each (index, element) ->
        $(element).addClass "blur"
      $(el).spin 'huge', '#777'
    else
      $(el).children(':not(.spinner)').each (index, element) ->
        $(element).removeClass "blur"
      $(el).spin false

ko.bindingHandlers.pickerDisable =
  update: (el, acc, allBindigns, kvm) ->
    $(el).data('disabled', acc()())

ko.bindingHandlers.bindDict =
  init: (el, acc, allBindigns, kvm) ->
    th = kvm["#{acc()}TypeaheadBuilder"]()
    th.setElement(el)
    # bind th.draw here, because we don't have ready th
    # during binding any more, see bug #1148
    $(el).next().on 'click', th.drawAll


ko.bindingHandlers.sort =
  update: (el, name, allBindings, viewModel, ctx) ->
    # add icon to show sorting direction
    defaultClass = 'icon-resize-vertical'
    $(el).prepend("<i class=#{defaultClass}></i>")

    # toggle sorting direction when user clicks on column header
    $(el).toggle(
      () ->
        # reset icon for others columns
        resetSort el, defaultClass
        # change icon to sorting ascending
        $(el).find('i').removeClass()
        $(el).find('i').addClass 'icon-arrow-up'
        # launch sorting
        ctx.$root.kvms.set_sorter "#{name()}SortAsc"
      ,
      () ->
        # reset icon for others columns
        resetSort el, defaultClass
        # change icon to sorting descending
        $(el).find('i').removeClass()
        $(el).find('i').addClass 'icon-arrow-down'
        # launch sorting
        ctx.$root.kvms.set_sorter "#{name()}SortDesc"
    )

    # reset icon to default (without sorting) for all column headers
    resetSort = (el, defaultClass) ->
      $(el).closest('thead')
           .children()
           .find('.icon-arrow-down, .icon-arrow-up')
           .removeClass()
           .addClass(defaultClass)

ko.bindingHandlers.renderField =
  init: (el, acc, allBindigns, fld, ctx) ->
    return if acc().meta.invisible
    tplid = acc().meta.widget
    tplid = "#{acc().type || 'text'}"
    tplid = "dictionary-many" if acc().type == "dictionary-set"
    tplid = "text" if acc().type == "ident"
    tpl   = Mustache.render $("##{tplid}-field-template").html(), acc()

    if ctx.$root.wrapFields
      # use some magick: wrap with div, so parser can grab all content
      # and serialize and parse again to make copy of template, so we
      # can populate ".content" part of the copy
      wrap = $("<div/>").html($("##{ctx.$root.wrapFields}-template").html())
      wrap.find(".content").html($(tpl))
      # use special context for wrappers, so we will know what field we are
      # rendering
      context = { kvm: ctx.$root.kvm, fld: fld }

    tpl = wrap.html() if wrap

    # use default context for usual fields so we can use default templates
    context ?= ctx.$root.kvm
    ko.utils.setHtml el, tpl
    ko.applyBindingsToDescendants(context, el)
    return { controlsDescendantBindings: true }

ko.bindingHandlers.renderGroup =
  init: (el, acc, allBindigns, fld, ctx) ->
    group = ctx.$root.showFields.groups[fld]
    fs = []
    for modelName, fields of group
      fs.push({kvm: acc()[modelName], field: fld}) for fld in fields

    ko.utils.setHtml el, $("#group-ro-template").html()
    ko.applyBindingsToDescendants({ fields: fs}, el)
    return { controlsDescendantBindings: true }

ko.bindingHandlers.render =
  init: (el, acc, allBindigns, ctx) ->
    return unless acc().field
    tplName = acc().field.type || 'text'
    tpl = $("##{tplName}-ro-template").html()
    console.error "Cant find template for #{tplName}" unless tpl
    ko.utils.setHtml el, tpl
    ko.applyBindingsToDescendants({kvm: acc().kvm, field: acc().field}, el)
    return { controlsDescendantBindings: true }

ko.bindingHandlers.expandAll =
  init: (el, acc, allBindigns, ctx, koctx) ->
    $(el).append("<label><i class='icon-plus-sign'></i></label>")
    $(el).click ->
      expanded = $(el).find('i').hasClass('icon-minus-sign')
      $(el).closest('table').find('.expand-contoller').each (key, tr) ->
        if expanded is $(tr).hasClass('expanded')
          $(tr).trigger 'click'
      $(el).find('i').toggleClass('icon-plus-sign').toggleClass('icon-minus-sign')

ko.bindingHandlers.expand =
  init: (el, acc, allBindigns, ctx, koctx) ->
    $(el).append("<label><i class='icon-plus-sign'></i></label>")
    $(el).click ->
      $(el).parent().next().toggleClass('hidden')
      $(el).toggleClass('expanded')
      $(el).find('i').toggleClass('icon-plus-sign').toggleClass('icon-minus-sign')

ko.bindingHandlers.eachNonEmpty =
  nonEmpty: (fnames, ctx, koctx) ->
    fns = _.reject fnames, (fname) ->
      g = koctx.$root.showFields.groups[fname]
      _.all (_.keys g), (m) ->
        kvm = ctx[m]
        _.all g[m], (f) ->
          if f
            _.isEmpty kvm[f.name]()
          else
            true

  init: (el, acc, allBindigns, ctx, koctx) ->
    fnames = ko.utils.unwrapObservable acc()
    fns = ko.bindingHandlers.eachNonEmpty.nonEmpty fnames, ctx, koctx
    ko.applyBindingsToNode el, {foreach: fns}, koctx
    { controlsDescendantBindings: true }
