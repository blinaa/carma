define [
    "utils",
    "model/main",
    "text!tpl/screens/contract.html",
    "screenman"],
  (utils, main, tpl, screenman) ->

    reformatDate = (date)->
      [_, d, m, y] = date.match(/([0-9]{2})\/([0-9]{2})\/([0-9]{4})/)
      "#{y}-#{m}-#{d}"

    getContractURL = (id) ->
      "/_/contract/#{id}"

    getContractsURL = (program) ->
      min = reformatDate $('#date-min').val()
      max = reformatDate $('#date-max').val()
      "/allContracts/#{program}?from=#{min}&to=#{max}"

    formatTableColumns = (program) ->
      tableCols =
            [ {name: "id", label: "#"}
            , {name: "isActive"}
            , "ctime"
            , "carVin"
            , "carMake"
            , "carModel"
            ]
      if program == '1'
        tableCols.push "carPlateNum"

      tableCols = tableCols.concat(
            [ "contractValidFromDate"
            , "contractValidUntilDate"
            , "contractValidUntilMilage"
            , "manager"
            ])

    findSame = (kvm, cb) ->
      vin = kvm['carVin']?()
      num = kvm['cardNumber']?()
      params  = ["id=#{kvm.id()}"]
      params.unshift "carVin=#{vin}"     if vin
      params.unshift "cardNumber=#{num}" if num
      $.getJSON "/contracts/findSame?#{params.join('&')}", cb

    mkTableSkeleton = (tableModel, fields) ->
      h = {}
      tableModel.fields.map (f) -> h[f.name] = f

      # remove columns that we don't have in model
      fieldNames = _.pluck tableModel.fields, 'name'
      filterFields = _.filter fields, (e) ->
        return true if typeof e is 'object'
        _.contains(fieldNames, e)

      fs = filterFields.map (field) ->
        # get field description
        # field may be a string or object with 'name', 'label' and 'fn' params
        # if type of field is string it should contain model fields name value
        desc = if field?.name then h[field.name] else h[field]

        # define field label
        defineLabel = ->
          # for fields which haven't label in model like 'id' field
          label = field.label if field?.label?
          # try to find field label in model
          label = desc.meta.label if desc?.meta?.label?
          label

        # define value render function by field type
        defineFnByType = ->
          if desc.type is 'dictionary'
            d = global.dictValueCache[desc.meta.dictionaryName]
            (contract) -> d[contract[field]] || contract[field] || ''
          else if desc.type is 'date'
            (contract) -> if contract[field]
                new Date(contract[field] * 1000).toString "dd.MM.yyyy"
              else ''
          else if desc.type is 'datetime'
            (contract) -> if contract[field]
                new Date(contract[field] * 1000).toString "dd.MM.yyyy HH:mm:ss"
              else ''
          else
            (contract) -> contract[field] || ''

        # define value render function by field name
        defineFnByName = ->
          name = if field?.name
            field.name
          else
            field
          if name is 'id'
            (contract) -> contract.id
          else if name is 'isActive'
            (contract) -> if contract.isActive == "true" then "✓" else ""
          else if name is 'owner'
            (contract) -> global.dictValueCache.users[contract.owner]

        # define field value render function
        defineFn = ->
          # for fields wich have predefined render function
          fn = field.fn if field?.fn?
          # try get by field type or name
          fn = do defineFnByName if not fn?
          fn = do defineFnByType if not fn?
          fn

        name = do defineLabel
        fn = do defineFn
        {name, fn}

      th = $('<thead/>')
      tr = $('<tr/>')
      th.append tr
      fs.map (f) -> tr.append $('<th/>', {html: f.name})

      { mkRow: ((obj) -> fs.map (f) -> f.fn obj)
      , headerHtml: th
      }

    dataTableOptions = ->
      # sorting function for 'isActive' column
      $.fn.dataTableExt.afnSortData['dom-checkbox'] = (oSettings, iColumn) ->
        aData = []
        $('td:eq('+iColumn+') input', oSettings.oApi._fnGetTrNodes(oSettings)).each(->
          aData.push(if @checked is true then "1" else "0"))
        aData

      aoColumnDefs: [
        sSortDataType: 'dom-checkbox'
        aTargets: [1]
      ]

      # enable horizontal scrolling
      sScrollX: "100%"
      sScrollXInner: "110%"

    modelSetup = (modelName, viewName, args, programModel) ->
      if args.id
        $('#render-contract').attr(
          "href",
          "/renderContract?prog=#{args.program}&ctr=#{args.id}")

      kvm = main.modelSetup(modelName, programModel)(
        viewName, args,
          permEl: "contract-permissions"
          focusClass: "focusable"
          refs: [])

      kvm['isActiveDisabled'](false)
      if _.find(global.user.roles, (r) -> r == 'contract_user')
        kvm['commentDisabled'](false)  if kvm['commentDisabled']
      if _.find(global.user.roles, (r) -> r == 'contract_admin')
        kvm['disableDixi'](true)

      kvm["updateUrl"] = ->
        h = window.location.href.split '/'
        if h[-3..-1][0] == "#contract"
          # /#contract/progid/id case
          u = h[-3..-1].join '/'
          global.router.navigate "#{h[-3..-2].join '/'}/#{kvm['id']()}",
            { trigger: false }
        else
          # /#contract/progid case
          global.router.navigate "#{h[-2..-1].join '/'}/#{kvm['id']()}",
            { trigger: false }

      # need this timeout, so this event won't be fired on saved
      # model, after it's first fetch
      utils.sTout 3000, ->
        kvm["dixi"].subscribe (v) ->
          return unless v
          findSame kvm, (r) ->
            return if _.isEmpty(r)
            txt = "В течении 30 дней уже были созданы контракты с
                   таким же vin или номером карты участника, их id:
                   #{_.pluck(r, 'id').join(', ')}. Всеравно сохранить?"
            return if confirm(txt)
            kvm["dixi"](false)

      return kvm

    programSetup = (viewName, args, programModel, programURL) ->
      $('#date-min').val (new Date).addDays(-30).toString('dd/MM/yyyy')
      $('#date-max').val (new Date).toString('dd/MM/yyyy')

      $('#new-contract-btn').on 'click', (e) ->
        e.preventDefault()
        location.hash = "#contract/#{args.program}"
        location.reload(true)

      modelName = "contract"
      kvm = modelSetup modelName, viewName, args, programModel

      tableModelURL = "#{programURL}&field=showtable"

      $.getJSON tableModelURL, (tableModel) ->
        sk = mkTableSkeleton tableModel, formatTableColumns args.program
        $table = $("#contracts-table")
        $table.append sk.headerHtml
        $table.append "<tbody/>"

        objsToRows = (objs) ->
          objs.map sk.mkRow

        tableParams =
          tableName: "contracts"
          objURL: getContractsURL args.program
        table = screenman.addScreen(modelName, ->)
          .addTable(tableParams)
          .setObjsToRowsConverter(objsToRows)
          .setDataTableOptions(do dataTableOptions)
          .on("click.datatable", "tr", ->
            id = @children[0].innerText
            k  = modelSetup modelName, viewName, {"id": id, "program": args.program}, programModel
            k["updateUrl"]()
            k)

        $("#filter-btn").on 'click', ->
          table.setObjs getContractsURL args.program

        if args.id == null && args.program == '2'
          kvm.carMake 'vw' if kvm.carMake
        kvm.dixi.subscribe ->
          $.getJSON getContractURL(kvm['id']()), (obj) ->
            table.dataTable.fnAddData sk.mkRow obj

        screenman.showScreen modelName

    screenSetup = (viewName, args) ->
      programURL = "/cfg/model/contract?pid=#{args.program}"
      $.getJSON programURL, (programModel) ->
        programSetup viewName, args, programModel, programURL

    template: tpl
    constructor: screenSetup
