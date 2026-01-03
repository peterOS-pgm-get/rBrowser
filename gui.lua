local api = unpack({ ... })

local window = pos.gui.Window('rBrowser', colors.black)
window.hideNameBar = true
window.exitOnHide = true
pos.gui.addWindow(window)

-- Top bar

local urlBar = pos.gui.TextInput(4, 1, window.w - 7, colors.gray, colors.white, api.setUrl)
urlBar.submitable = true
window:addElement(urlBar)
api.setUrlBarElement(urlBar)
local refreshButton = pos.gui.Button(2,1,1,1,colors.gray,colors.lightGray,'*',api.refresh)
window:addElement(refreshButton)
api.refreshButton = refreshButton
local backButton = pos.gui.Button(1,1,1,1,colors.gray,colors.lightGray,'<',api.back)
window:addElement(backButton)
local urlSep = pos.gui.TextBox(3, 1, colors.gray, colors.lightGray, '|')
window:addElement(urlSep)
local bookmarkButton = pos.gui.Button(window.w - 3, 1, 1, 1, colors.gray, colors.lightGray, '+', function()
    api.bookmark(urlBar.text)
end)
api.bookmarkButton = bookmarkButton
window:addElement(bookmarkButton)
local homeButton = pos.gui.Button(window.w - 2, 1, 1, 1, colors.gray, colors.lightGray, 'X ', function()
    api.goHome()
end)
window:addElement(homeButton)
local btnSep = pos.gui.TextBox(window.w - 1, 1, colors.gray, colors.lightGray, ' ')
window:addElement(btnSep)

local page = pos.gui.ScrollField(1, 2, window.w, window.h - 1)
window:addElement(page)
api.setPageElement(page)


local bookmarkWindow = pos.gui.Window('Bookmark', colors.cyan)
pos.gui.addWindow(bookmarkWindow)
api.bookmarkWindow = bookmarkWindow
bookmarkWindow:hide()
bookmarkWindow:setSize(15, 5)
bookmarkWindow:setPos(window.w - 17, 1)
bookmarkWindow.exitOnHide = false

local bW_nameInput = pos.gui.TextInput(1, 3, 15)
bookmarkWindow:addElement(bW_nameInput)
api.bookmarkWindowInput = bW_nameInput

local bW_saveBtn = pos.gui.Button(1,5,4,1,colors.green,colors.white,'Save', function()
    api.bookmarks[urlBar.text] = bW_nameInput.text
    api.saveBookmarks()
    bookmarkWindow:hide()
end)
bookmarkWindow:addElement(bW_saveBtn)

local bW_delBtn = pos.gui.Button(6,5,6,1,colors.red,colors.white,'Delete', function()
    api.bookmarks[urlBar.text] = nil
    bookmarkButton.fg = colors.lightGray
    api.saveBookmarks()
    bookmarkWindow:hide()
end)
bookmarkWindow:addElement(bW_delBtn)

return {
    window = window,
    page = page,
    urlBar = urlBar
}