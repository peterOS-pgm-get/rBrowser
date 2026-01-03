pos.require("net.rttp")

local api = {
    url = {
        proto = 'rttp',
        domain = '',
        path = '',
    },
    history = {},
    log = pos.Logger('rBrowser.log'),
    urlBarElement = nil, ---@type TextInput
    pageElement = nil, ---@type ScrollField
    bookmarkButton = nil, ---@type Button
    bookmarkWindow = nil, ---@type Window
    bookmarkWindowInput = nil, ---@type TextInput
    refreshButton = nil, ---@type Button
    _cookies = {}, ---@type { [string]: string }
    _refreshTimer = nil, ---@type number?
    _waitingMsgId = -1, ---@type number
}

function api.addToHistory()
    local last = {
        proto = api.url.proto,
        domain = api.url.domain,
        path = api.url.path
    }
    table.insert(api.history, last)
end

---Sets the url bar TextInput elements
---@param urlBar TextInput
function api.setUrlBarElement(urlBar)
    api.urlBarElement = urlBar
end

function api.setPageElement(page)
    api.pageElement = page
end

function api.setPath(path, secure)
    api.addToHistory()
    if not path:start('/') then
        path = '/' .. path
    end
    api.url.path = path
    if api.urlBarElement then
        api.urlBarElement:setText(api.getUrl(true))
        api.setSecure(secure)
    end
    api.refresh()
end

function api.setSecure(secure)
    if not api.urlBarElement then
        return
    end

    if secure then
        api.urlBarElement.fg = colors.yellow
    else
        api.urlBarElement.fg = colors.white
    end
end

function api.appendPath(path)
    if path:start('/') then
        api.setPath(path)
    else
        api.setPath(fs.combine(api.url.path, path))
    end
end

function api.goHome()
    api.pageElement:clearElements()
    api.urlBarElement:setText('')
    api.url.proto, api.url.domain, api.url.path = '', '', ''
    api.bookmarkButton.fg = colors.lightGray

    local y = 3
    api.pageElement:addElement(pos.gui.TextBox(1,2,nil,nil,'Bookmarks:'))
    for url,name in pairs(api.bookmarks) do
        local btn = pos.gui.Button(1,y,#name,1,colors.gray,colors.lightBlue,name,function()
            api.setUrl(url)
        end)
        api.pageElement:addElement(btn)
        y = y + 1
    end
end

function api.setUrl(url)
    if (url == '') then
        api.goHome()
        return
    end
    api.addToHistory()
    api.url.proto, api.url.domain, api.url.path = net.splitUrl(url)
    if not api.url.proto then
        api.url.proto = 'rttp'
    end
    api.url.path = '/' .. api.url.path
    if api.urlBarElement then
        api.urlBarElement:setText(api.getUrl(true))
    end
    api.refresh()
end

function api.getUrl(hideRTTP, path)
    if hideRTTP and api.url.proto == 'rttp' then
        return api.url.domain .. api.url.path
    end
    if path then
        return api.url.proto .. '://' .. api.url.domain .. path
    end
    return api.url.proto .. '://' .. api.url.domain .. api.url.path
end

local pageElements = {} ---@type UiElement[]
local formElements = {} ---@type TextInput[]

local refreshTimer = nil
function api.refresh()
    api.log:info("Loading page %s://%s%s", api.url.proto or 'rttp', api.url.domain, api.url.path or '/')

    local dest = api.url.domain ---@type string|number
    local dIp = net.ipToNumber(dest)
    if dIp > 0 then
        dest = dIp
    end

    if api.urlBarElement then
        api.urlBarElement:setText(api.getUrl(true))
        api.setSecure(false)
    end
    if api.refreshButton then
        api.refreshButton.text = 'O'
    end
    pos.gui.redrawWindows()

    local rt = rttp.get(dest, api.url.path, api._cookies[dest])
    if type(rt) == "string" then
        api._refreshFinish(rt)
        return
    end
    api._waitingMsgId = rt
    api._refreshTimer = os.startTimer(5)
end

---@param msg NetMessage
function api.__onNetMessage(msg)
    if api._waitingMsgId < 0 or type(msg.dest) == "string" then
        return
    end
    if msg.header.type == 'rttp' and msg.msgid == api._waitingMsgId then
        ---@cast msg RttpMessage
        api._waitingMsgId = -1
        os.cancelTimer(api._refreshTimer)
        api._refreshTimer = nil
        api._refreshFinish(msg)
    end
end

---@param rt RttpMessage|string
function api._refreshFinish(rt)
    local dest = api.url.domain ---@type string|number
    local dIp = net.ipToNumber(dest)
    if dIp > 0 then
        dest = dIp
    end

    api.log:info("Finishing page load")

    if api.refreshButton then
        api.refreshButton.text = '*'
    end
    
    api.bookmarkWindow:hide()
    if api.bookmarks[api.getUrl(true)] then
        api.bookmarkButton.fg = colors.green
        api.bookmarkWindowInput:setText(api.bookmarks[api.getUrl(true)])
    else
        api.bookmarkButton.fg = colors.lightGray
    end

    api.pageElement:clearElements()

    if type(rt) == "string" then
        api.log:error('Network error on GET:' .. api.getUrl() .. ' : ' .. rt)
        local text = pos.gui.TextBox(1, 1, nil, colors.red, 'Net Error: ' .. rt)
        api.pageElement:addElement(text)
        return
    end
    
    -- api.log:debug(textutils.serialiseJSON(rt.header))
    if rt.header.cookies then
        -- api.log:info('Storing cookies')
        if not api._cookies[dest] then
            api._cookies[dest] = {}
        end
        for name, cookie in pairs(rt.header.cookies) do
            -- api.log:debug('Storing cookie "' .. name .. '": "' .. cookie .. '"')
            if cookie == '' then
                api._cookies[dest][name] = nil
            else
                api._cookies[dest][name] = cookie
            end
        end
    end
    
    if rt.header.code == rttp.responseCodes.movedTemporarily or rt.header.code == rttp.responseCodes.movedPermanently or rt.header.code == rttp.responseCodes.seeOther then
        api.setPath(rt.header.redirect)
        api.log:info("Redirecting to %s", rt.header.redirect)
        return
    end
    if rt.header.code ~= rttp.responseCodes.okay then
        api.log:warn('Received response ' .. rttp.codeName(rt.header.code))
        -- local text = pos.gui.TextBox(1, 1, nil, colors.red, 'Error: ' .. rt.body)
        -- api.pageElement:addElement(text)
        -- return
    end

    if rt.header.certificate then
        api.setSecure(true)
    else
        api.setSecure(false)
    end
    if rt.header.contentType == 'text/plain' then
        local text = pos.gui.TextBox(1, 1, nil, nil, rt.body--[[@as string]])
        api.pageElement:addElement(text)
        return
    elseif rt.header.contentType == 'table/rtml' then
        local lInp = nil
        local nEls = {}
        pageElements = {}
        formElements = {}
        for i = 1, #rt.body do
            local rtmlEl = rt.body[i] ---@type RTMLElement
            local guiEl = nil
            local color = rtmlEl.color
            if type(color) == 'string' then
                color = colors[color]
            end
            local bgColor = rtmlEl.bgColor
            if type(bgColor) == 'string' then
                bgColor = colors[bgColor]
            end
            if rtmlEl.type == "TEXT" then
                guiEl = pos.gui.TextBox(rtmlEl.x, rtmlEl.y, bgColor or colors.black, color or colors.white, rtmlEl.text)
            elseif rtmlEl.type == "LINK" then
                guiEl = pos.gui.Button(rtmlEl.x, rtmlEl.y, string.len(rtmlEl.text), 1, bgColor or colors.gray, color or colors.lightBlue, rtmlEl.text,
                    function()
                        api.appendPath(rtmlEl.href)
                    end)
            elseif rtmlEl.type == "DOM-LINK" then
                guiEl = pos.gui.Button(rtmlEl.x, rtmlEl.y, string.len(rtmlEl.text), 1, bgColor or colors.gray, color or colors.lightBlue, rtmlEl.text,
                    function()
                        api.setUrl(rtmlEl.href)
                    end)
            elseif rtmlEl.type == 'INPUT' then
                guiEl = pos.gui.TextInput(rtmlEl.x, rtmlEl.y, rtmlEl.len, bgColor or colors.gray, color or colors.white, function(text) end)
                guiEl.name = rtmlEl.name
                if rtmlEl.hide then
                    guiEl.hideText = true
                end
                if rtmlEl.next then
                    table.insert(nEls, { fE = guiEl, next = rtmlEl.next })
                end
                if lInp then lInp.next = guiEl end
                lInp = guiEl
                formElements[rtmlEl.name] = guiEl
            elseif rtmlEl.type == 'BUTTON' then
                guiEl = pos.gui.Button(rtmlEl.x, rtmlEl.y, string.len(rtmlEl.text), 1, bgColor or colors.green, color or colors.white, rtmlEl.text,
                    function()
                        local msg
                        local path = api.url.path
                        if rtmlEl.action == 'SUBMIT' then
                            local rsp = {
                                vals = {},
                                type = "BUTTON_SUBMIT",
                            }
                            for name, el in pairs(formElements) do
                                rsp.vals[name] = el.text
                            end

                            msg = rttp.postSync(dest, path, 'object/lua', rsp, api._cookies[dest])
                        elseif rtmlEl.action == 'PUSH' then
                            local rsp = {
                                type = "BUTTON_PUSH",
                                id = rtmlEl.id,
                            }
                            path = '/' .. fs.combine(path, rtmlEl.href)

                            msg = rttp.postSync(dest, path, 'object/lua', rsp, api._cookies[dest])
                        else
                            api.log:warn('Unknown button action: ' .. rtmlEl.action)
                            return
                        end
                        
                        if type(msg) ~= 'string' then
                            if msg.header.cookies then
                                -- api.log:info('Storing cookies')
                                if not api._cookies[dest] then
                                    api._cookies[dest] = {}
                                end
                                for name, cookie in pairs(msg.header.cookies) do
                                    -- api.log:debug('Storing cookie "' .. name .. '": "' .. cookie .. '"')
                                    api._cookies[dest][name] = cookie
                                end
                            end

                            api.log:debug("Button response code " .. msg.header.code)
                            if msg.header.code == rttp.responseCodes.movedTemporarily then
                                api.appendPath(msg.header.redirect)
                            elseif msg.header.code == rttp.responseCodes.okay then
                                if msg.header.contentType == "text/plain" then
                                    api.log:debug("Button Response: " .. msg.body)
                                end
                            else
                                if msg.header.contentType == "text/plain" then
                                    api.log:warn('Button error on POST:' .. api.getUrl(false,path) .. ' : ' .. msg.body)
                                else
                                    api.log:warn('Button error on POST:' .. api.getUrl(false,path))
                                end
                            end
                        else
                            api.log:warn("Network error on POST:" .. api.getUrl(false,path) .. " : " .. msg)
                        end
                    end)
            end
            if guiEl then
                if rtmlEl.id then
                    pageElements[rtmlEl.id] = guiEl
                end
                api.pageElement:addElement(guiEl)
            end
        end
        for _, t in pairs(nEls) do
            if t.next then
                if formElements[t.next] then
                    t.fE.next = formElements[t.next]
                else
                    api.log:warn('Form element '..t.fE.name..' indicated element "'..t.next..'" as next, but it does not exist')
                end
            end
        end
        return
    end
end

function api.back()
    local last = table.remove(api.history, #api.history)
    api.url.domain = last.domain
    api.url.path = last.path
    api.url.proto = last.proto
    api.refresh()
end

api.bookmarks = {} ---@type table<string, string> Bookmark names indexed by URL
local bookmarkPath = '%appdata%/browser/bookmarks'
function api.loadBookmarks()
    if not fs.exists(bookmarkPath .. '.json') then
        if not fs.exists(bookmarkPath .. '.lua') then
            return
        end

        api.log:info('Translating LUA bookmark file to JSON')

        local f = fs.open(bookmarkPath .. '.lua', 'r')
        if not f then
            api.log:error('Could not open bookmark file')
            return
        end

        local bookmarksLUA = textutils.unserialise(f.readAll())
        f.close()
        if not bookmarksLUA then
            api.log:error('Bookmark file corrupted')
            return
        end
        api.bookmarks = {}
        for _,bkm in pairs(bookmarksLUA) do
            api.bookmarks[bkm.href] = bkm.name
        end
        api.saveBookmarks()
        return
    end

    local f = fs.open(bookmarkPath .. '.json', 'r')
    if not f then
        api.log:error('Could not open bookmark file')
        return
    end
    local bookmarks = textutils.unserialiseJSON(f.readAll())
    f.close()
    if not bookmarks then
        api.log:error('Bookmark file corrupted')
        return
    end
    api.bookmarks = bookmarks
end

function api.saveBookmarks()
    local f = fs.open(bookmarkPath .. '.json', 'w')
    if not f then
        api.log:warn('Unable to save to bookmark file')
        return
    end
    f.write(textutils.serialiseJSON(api.bookmarks))
    f.close()
end

function api.bookmark()
    local url = api.getUrl(true)
    if api.bookmarks[url] then
        api.bookmarkWindow:show()
    else
        api.bookmarks[url] = url
        api.bookmarkButton.fg = colors.green
        api.bookmarkWindowInput:setText(url)
    end
    api.saveBookmarks()
end

api.gui = loadfile('gui.lua')(api)

api.loadBookmarks()
api.goHome()
net.registerMsgHandler(api.__onNetMessage)
pos.addEventHandler(function(event) 
    ---@cast event TimerEvent
    local _, timer = table.unpack(event)
    if timer == api._refreshTimer then
        api._refreshFinish('timeout')
    end
end, 'timer', 'rBrowser-Timer')

return api
