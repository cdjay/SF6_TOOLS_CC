-- We want better translations! If you can help, please contact me on Nexus Mods.
local sdk = sdk

local __ja = {
    main_menu = "メインメニュー",
    training_mode = "トレーニングモード",
    booting = "%sに起動中…",
    switch_prompt = "起動先切り替え：スペースキー",
    first_boot = "Faster Startup: 初回起動には少し時間がかかる場合があります。\nしばらくお待ちください。",
    dlc_detected = "新しいDLCが検出されました！\n完全なログイン処理を実行中です。しばらくお待ちください。"
}

local __en = {
    main_menu = "Main Menu",
    training_mode = "Training Mode",
    booting = "Booting into %s...",
    switch_prompt = "Switch boot destination: Space key",
    first_boot = "Faster Startup: First boot may take a little time...\nThanks for your patience!",
    dlc_detected = "New DLC detected!\nPerforming full login process. Please wait..."
}

local __fr = {
    main_menu = "menu principal",
    training_mode = "mode entraînement",
    booting = "Lancement de %s...",
    switch_prompt = "Changer la destination de démarrage : touche Espace",
    first_boot = "Faster Startup: Le premier démarrage peut prendre un peu de temps...\nMerci de patienter !",
    dlc_detected = "Nouveau DLC détecté !\nConnexion complète en cours. Veuillez patienter..."
}

local __de = {
    main_menu = "Hauptmenü",
    training_mode = "Trainingsmodus",
    booting = "%s wird gestartet...",
    switch_prompt = "Boot-Ziel wechseln: Leertaste",
    first_boot = "Faster Startup: Der erste Start kann etwas länger dauern...\nBitte habe etwas Geduld!",
    dlc_detected = "Neues DLC erkannt!\nVollständiger Login-Vorgang läuft. Bitte warten..."
}

local __it = {
    main_menu = "menu principale",
    training_mode = "modalità addestramento",
    booting = "Avvio di %s...",
    switch_prompt = "Cambio destinazione di avvio: barra spaziatrice",
    first_boot = "Faster Startup: Il primo avvio potrebbe richiedere un po' di tempo...\nGrazie per la pazienza!",
    dlc_detected = "Nuovo DLC rilevato!\nAccesso completo in corso. Attendere prego..."
}

local __es = {
    main_menu = "menú principal",
    training_mode = "modo de entrenamiento",
    booting = "Iniciando %s...",
    switch_prompt = "Cambiar destino de arranque: barra espaciadora",
    first_boot = "Faster Startup: El primer inicio puede tardar un poco...\n¡Gracias por tu paciencia!",
    dlc_detected = "¡Nuevo DLC detectado!\nEjecutando proceso de inicio completo. Por favor espera..."
}

local __ru = {
    main_menu = "главное меню",
    training_mode = "режим тренировки",
    booting = "Запуск %s...",
    switch_prompt = "Смена цели загрузки: пробел",
    first_boot = "Faster Startup: Первый запуск может занять немного времени...\nПожалуйста, подождите.",
    dlc_detected = "Обнаружено новое DLC!\nВыполняется полный процесс входа. Пожалуйста, подождите..."
}

local __pl = {
    main_menu = "menu główne",
    training_mode = "tryb treningowy",
    booting = "Uruchamianie %s...",
    switch_prompt = "Zmień cel uruchamiania: spacja",
    first_boot = "Faster Startup: Pierwsze uruchomienie może chwilę potrwać...\nProsimy o cierpliwość!",
    dlc_detected = "Wykryto nowe DLC!\nTrwa pełny proces logowania. Proszę czekać..."
}

local __pt_br = {
    main_menu = "menu principal",
    training_mode = "modo de treinamento",
    booting = "Iniciando %s...",
    switch_prompt = "Trocar destino de inicialização: barra de espaço",
    first_boot = "Faster Startup: A primeira inicialização pode levar algum tempo...\nAgradecemos pela paciência!",
    dlc_detected = "Novo DLC detectado!\nExecutando processo completo de login. Por favor, aguarde..."
}

local __kr = {
    main_menu = "메인 메뉴",
    training_mode = "훈련 모드",
    booting = "%s에 부팅 중...",
    switch_prompt = "부팅 대상 변경: 스페이스 키",
    first_boot = "Faster Startup: 첫 부팅에는 시간이 조금 걸릴 수 있습니다.\n잠시만 기다려 주세요!",
    dlc_detected = "새 DLC가 감지되었습니다!\n전체 로그인 절차를 진행 중입니다. 잠시만 기다려 주세요."
}

local __zh_cn = {
    main_menu = "主菜单",
    training_mode = "训练模式",
    booting = "正在启动 %s...",
    switch_prompt = "切换启动目标：空格键",
    first_boot = "Faster Startup: 首次启动可能需要一些时间…\n请耐心等待！",
    dlc_detected = "检测到新DLC！\n正在执行完整登录流程，请稍候..."
}

local __zh_tw = {
    main_menu = "主選單",
    training_mode = "訓練模式",
    booting = "正在啟動 %s...",
    switch_prompt = "切換啟動目標：空白鍵",
    first_boot = "Faster Startup: 首次啟動可能需要一些時間…\n請耐心等候！",
    dlc_detected = "偵測到新DLC！\n正在執行完整登入流程，請稍候..."
}

local __ar = {
    main_menu = "القائمة الرئيسية",
    training_mode = "وضع التدريب",
    booting = "يتم تشغيل %s...",
    switch_prompt = "تغيير وجهة التمهيد: مفتاح المسافة",
    first_boot = "Faster Startup: قد يستغرق التشغيل الأول بعض الوقت...\nيرجى التحلي بالصبر!",
    dlc_detected = "تم اكتشاف محتوى إضافي جديد!\nجارٍ تنفيذ عملية تسجيل الدخول الكاملة. يرجى الانتظار..."
}

local __es_latam = {
    main_menu = "menú principal",
    training_mode = "modo de entrenamiento",
    booting = "Iniciando %s...",
    switch_prompt = "Cambiar destino de arranque: barra espaciadora",
    first_boot = "Faster Startup: El primer inicio puede tardar un poco...\n¡Gracias por tu paciencia!",
    dlc_detected = "¡Nuevo DLC detectado!\nEjecutando proceso de inicio completo. Por favor espera..."
}

local this = {}
this.DEFAULT_LANGUAGE = 1
this.text_prefererences = {
    [0] = __ja,
    [1] = __en,
    [2] = __fr,
    [4] = __de,
    [3] = __it,
    [5] = __es,
    [6] = __ru,
    [7] = __pl,
    [10] = __pt_br,
    [11] = __kr,
    [12] = __zh_tw,
    [13] = __zh_cn,
    [21] = __ar,
    [32] = __es_latam
}
function this.copy_table(original)
    local copy = {}
    for key, value in pairs(original) do
        copy[key] = value
    end
    return copy
end
function this.get_init_lang_table()
    local mGUI = sdk.get_native_singleton("via.gui.GUISystem")
    if not mGUI then return this.DEFAULT_LANGUAGE end
    return this.text_prefererences[sdk.call_native_func(mGUI, sdk.find_type_definition("via.gui.GUISystem"), "get_MessageLanguage") or this.DEFAULT_LANGUAGE]
end
this.retval = this.copy_table(this.get_init_lang_table())



sdk.hook(sdk.find_type_definition("via.gui.GUISystem"):get_method("set_MessageLanguage(via.Language)"), function(args)
    local code = sdk.to_int64(args[2])
    local lang_table = this.text_prefererences[code] or this.text_prefererences[1]
    for k, v in pairs(this.retval) do
        this.retval[k] = lang_table[k]
    end
end)

return this.retval