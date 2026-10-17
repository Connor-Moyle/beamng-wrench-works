-- Wrench Works: the garage's player-facing text, in one place (#51). Pure (tested by tools/strings_test.js).
-- The garage screen gets this table once (slrr_garage.requestStrings, event slrrGarageStrings) and says $scope.t('bar.photo.title', 'Photo'): the second
-- argument is what shows before the table has arrived. Keys are area.name.part. To reword or translate the garage, change this file.

local M = {}

M.TEXT = {
  ['bar.advancetime.desc'] = 'move the clock on three hours',
  ['bar.advancetime.title'] = 'Advance time',
  ['bar.carinfo.desc'] = 'details of this car',
  ['bar.carinfo.title'] = 'Car info',
  ['bar.catalog.desc'] = 'order new parts',
  ['bar.catalog.title'] = 'Catalog',
  ['bar.driveout.desc'] = 'fit everything and hit the street',
  ['bar.driveout.title'] = 'Drive out',
  ['bar.drivers.desc'] = 'who sits behind the wheel',
  ['bar.drivers.title'] = 'Drivers',
  ['bar.lift.desc'] = 'raise or lower the car',
  ['bar.lift.title'] = 'Lift',
  ['bar.mechanic.desc'] = 'install and remove parts',
  ['bar.mechanic.title'] = 'Mechanic',
  ['bar.paintbooth.desc'] = 'respray the car',
  ['bar.paintbooth.title'] = 'Paint booth',
  ['bar.photo.desc'] = 'hide the screen and save a picture of the car (screenshots/slrr_garage)',
  ['bar.photo.title'] = 'Photo',
  ['bar.photomode.desc'] = 'the game\'s own photo mode (angles, lenses, effects)',
  ['bar.photomode.title'] = 'Photo mode',
  ['bar.races.desc'] = 'pick a race or a track',
  ['bar.races.title'] = 'Races',
  ['bar.services.desc'] = 'oil, coolant, battery, nitrous, engine rebuild and repairs',
  ['bar.services.title'] = 'Services',
  ['bar.settings.desc'] = 'money, prices, damage and more',
  ['bar.settings.title'] = 'Settings',
  ['bar.showcase.desc'] = 'the camera turns slowly round the car',
  ['bar.showcase.title'] = 'Showcase',
  ['bar.testengine.desc'] = 'start or stop it where it stands',
  ['bar.testengine.title'] = 'Test engine',
  ['bar.tune.desc'] = 'every tuning item of the car on the right; or click a part to adjust it',
  ['bar.tune.title'] = 'Tune',
  ['bar.wholecar.desc'] = 'reset the camera',
  ['bar.wholecar.title'] = 'Whole car',
  ['tab.drivers'] = 'Drivers',
  ['tab.races'] = 'Races',
  ['tab.services'] = 'Services',
}

function M.t(key) return M.TEXT[key] or tostring(key) end

return M
