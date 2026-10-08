local this = {}
this.TICKER_TIME = 0.75 -- (sec)
this.SWITCHER_KEY_CODE = 0x20 -- Windows virtual key code
this.SHOW_FIRST_TICKER = true -- MAKE THIS false => SILENT MODE
this.FIRST_DESTINATION = 1 -- 1 -> main menu | 2 -> training 
this.SAFE_MODE = true -- If true, do not agressively skip login part
this.SAVE_PER_USER = true -- If true, save file is associated to Steam user id(just locally)

return this
