net.setup()

if not _G.pgm.rBrowser then
    _G.pgm.rBrowser = {
        api = dofile('api.lua')
    }
end

local api = _G.pgm.rBrowser.api
api.gui.window:show()
api.gui.urlBar.focused = true
pos.gui.run()