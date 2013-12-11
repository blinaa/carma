define [ "utils"
       , "json!/cfg/model/Case"
       , "json!/cfg/model/Service"
       , "json!/cfg/model/Towage"
       ] ,(Utils, ms...) ->

  allModels = arrToObj 'name', ms

  resultFields =
    Case: [
      "id"
      "contact_phone1"
      "contact_phone2"
      "contact_phone3"
      "contact_phone4"
      "contact_ownerPhone1"
      "contact_ownerPhone2"
      "contact_ownerPhone3"
      "contact_ownerPhone4"
      "callDate"
      "car_plateNum"
      "car_vin"
      "program"
      "city"
      "car_make"
      "car_model"
      "cardNumber_cardNumber"
      ]
    Service: [
      "type"
      "contractor_partnerId"
      "createTime"
      ]
    Towage: [
      "towDealer_partnerId"
      ]

  # make deep copy of required models, so we wont brake them somewhere
  all = $.extend true, {}, allModels
  for n,m of all
    m.fields = _.filter m.fields, (f) -> _.contains resultFields[n], f.name
  arrToObj 'name', all
