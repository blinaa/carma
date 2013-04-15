define [
    "utils",
    "model/main",
    "text!tpl/screens/contract.html"],
  (utils, main, tpl) ->
    template: tpl
    constructor: (viewName, args) ->
      modelHref = "/cfg/model/contract?pid=#{args.program}"
      modelTable = "#{modelHref}&field=showtable"
      setupModel = (args) ->
        if args.id
          $('#render-contract').attr(
            "href",
            "/renderContract?prog=#{args.program}&ctr=#{args.id}")
        kvm = main.modelSetup("contract", modelHref)(
          viewName, args,
            permEl: "contract-permissions"
            focusClass: "focusable"
            refs: [])

        if _.find(global.user.roles, (r) -> r == 'contractUser')
          kvm['commentDisabled'](false) if kvm['commentDisabled']
          kvm['isActiveDisabled'](false)  if kvm['isActiveDisabled']
        if _.find(global.user.roles, (r) -> r == 'contractAdmin')
          kvm['disableDixi'](true)
        return kvm

      kvm = setupModel args
      $.getJSON modelTable, (model) ->
        tableCols =
              [ {name: "#", fn: (o) -> o.id}
              , "ctime"
              , "carVin"
              , "carMake"
              , "carModel"
              ]
        if args.program == '1'
          tableCols.push "carPlateNum"

        tableCols.concat(
              [ "contractValidFromDate"
              , "contractValidUntilDate"
              , "contractValidUntilMilage"
              , "manager"
              ])

        sk = mkTableSkeleton model, tableCols
        $.fn.dataTableExt.oStdClasses.sLength = "dataTables_length form-inline"
        $.fn.dataTableExt.oStdClasses.sFilter = "dataTables_filter form-inline"

        t = $("#contracts-table")
        return if t.hasClass("dataTable")

        t.append sk.headerHtml
        t.append "<tbody/>"

        t.on("click.datatable", "tr", ->
          id = this.children[0].innerText
          setupModel {"id": id}
        )

        dt = utils.mkDataTable t

        $('#date-min').val (new Date).addDays(-30).toString('dd/MM/yyyy')
        $('#date-max').val (new Date).toString('dd/MM/yyyy')

        fillTable = (objs) ->
          dt.fnClearTable()
          dt.fnAddData(objs.map sk.mkRow)

        $("#filter-btn").on 'click', ->
          getContracts args.program, fillTable

        getContracts args.program, fillTable

        if args.id == null && args.program == '2'
          kvm.carMake 'vw'
        kvm.maybeId.subscribe ->
          getContracts kvm['id'](), (objs) -> dt.fnAddData objs.map sk.mkRow

reformatDate = (date)->
  [_, d, m, y] = date.match(/([0-9]{2})\/([0-9]{2})\/([0-9]{4})/)
  "#{y}-#{m}-#{d}"

getContracts = (args, cb) ->
  min = reformatDate $('#date-min').val()
  max = reformatDate $('#date-max').val()
  path = "/allContracts/#{args}?from=#{min}&to=#{max}"
  $.getJSON path, cb

mkTableSkeleton = (model, fields) ->
  h = {}
  model.fields.map (f) -> h[f.name] = f

  # remove columns that we don't have in model
  fieldNames = _.pluck model.fields, 'name'
  filterFields = _.filter fields, (e) ->
    return true if typeof e is 'object'
    _.contains(fieldNames, e)

  fs = filterFields.map (f) ->
    if typeof f == 'string'
      desc = h[f]
      {name: desc.meta.label
      ,fn:
        if desc.type == 'dictionary'
          d = global.dictValueCache[desc.meta.dictionaryName]
          (v) -> d[v[f]] || v[f] || ''
        else if desc.type == 'date'
          (v) -> if v[f]
              new Date(v[f] * 1000).toString "dd.MM.yyyy"
            else ''
        else if desc.type == 'datetime'
          (v) -> if v[f]
              new Date(v[f] * 1000).toString "dd.MM.yyyy HH:mm:ss"
            else ''
        else
          (v) -> v[f] || ''
      }
    else
      f

  th = $('<thead/>')
  tr = $('<tr/>')
  th.append tr
  fs.map (f) -> tr.append $('<th/>', {html: f.name})

  { mkRow: ((obj) -> fs.map (f) -> f.fn obj)
  , headerHtml: th
  }
