"""The Play frames: which screen fills each slot, and its caption per locale.

Pure data, stdlib only: `compose_play.py` draws from it and
`check_listing.py` holds it to the listing's rules (translation rules,
another platform's words, emoji, capitals) without needing Pillow.
"""

NNBSP = chr(0x202F)     # French: before "?" — typed literally, it vanishes in review

# Play locale → the language tag the capture run names its raws with.
LANG = {"en-US": "en", "ru-RU": "ru", "es-ES": "es", "pt-BR": "pt-BR",
        "de-DE": "de", "fr-FR": "fr", "it-IT": "it"}

# Eight slots, Play's maximum. The order follows the iOS set: the three that
# sell first (Today, the rating, the hands-free hold), then the ones that
# confirm. The second field is the raw's screen name (ScreenshotWalk's
# `<lang>-light-<screen>.png`); `None` is the widget, which WidgetScreenshots
# writes as `widget-<lang>-light-<size>.png`.
#
# Left out, and why: the rest screen and the calendar — "rest is timed for you"
# and "there is a calendar" are what a visitor assumes of any training app,
# which is why `rest_` left the iOS set in 2.1.0; the probe, the technique sheet
# and the comeback card — no Android capture path reaches them (no seed puts a
# probe or a break in front of ScreenshotWalk), and a frame is not drawn from a
# path that cannot produce it.
SLOTS = [
    ("01-today", "today"),
    ("02-rating", "rating"),
    ("03-handsfree", "holdintro"),
    ("04-summary", "summary"),
    ("05-skip", "set"),
    ("06-progress", "progress"),
    ("07-widget", None),
    ("08-howitworks", "howitworks"),
]

# (headline lines, subtitle). All but 07-widget are the shipped iOS captions
# (store/appstore/tools/compose.py), each re-read against the Android screen
# it now sits on.
CAPTIONS = {
    "01-today": {
        "en-US": (["Zero setup."], "Open the app — your workout is ready."),
        "ru-RU": (["Ноль настроек."], "Открой приложение — тренировка готова."),
        "es-ES": (["Cero configuración."], "Abre la app: tu entrenamiento ya está listo."),
        "pt-BR": (["Zero configuração."], "Abra o app — seu treino está pronto."),
        "de-DE": (["Nichts einzurichten"], "Öffne die App – dein Training steht bereit."),
        "fr-FR": (["Rien à configurer."], "Ouvre l’app, la séance est prête."),
        "it-IT": (["Zero configurazioni."], "Apri l’app: l’allenamento è pronto."),
    },
    "02-rating": {
        "en-US": (["It adapts to you"], "One tap after the workout — the next one adapts."),
        "ru-RU": (["Подстраивается", "под тебя"], "Одно касание после тренировки — следующая подстроится."),
        "es-ES": (["Se adapta a ti"], "Un toque después del entrenamiento: el siguiente se adapta."),
        "pt-BR": (["Se adapta a você"], "Um toque depois do treino — o próximo se adapta."),
        "de-DE": (["Es passt sich dir an"], "Ein Fingertipp nach dem Training – das nächste passt sich an."),
        "fr-FR": (["S’adapte à toi"], "Une pression après la séance, la suivante s’ajuste."),
        "it-IT": (["Si adatta a te"], "Un tocco dopo l’allenamento — il prossimo si adatta."),
    },
    # The hold's intro screen says it in words: "Runs on its own from here —
    # sound counts you in and out. Put the phone down." (WorkoutFlowViewWork.kt).
    "03-handsfree": {
        "en-US": (["Put the phone down"], "One tap runs the whole exercise. Sound counts you in and out."),
        "ru-RU": (["Телефон", "можно положить"], "Одно касание — и упражнение идет само. Звук ведет счет."),
        "es-ES": (["Deja el teléfono", "en el suelo"], "Un toque hace todo el ejercicio. El sonido cuenta por ti."),
        "pt-BR": (["Largue o celular", "no chão"], "Um toque comanda todo o exercício. O som marca início e fim."),
        "de-DE": (["Leg das Handy weg"], "Ein Tipp für die ganze Übung – der Ton zählt dich rein und raus."),
        "fr-FR": (["Pose le téléphone"], "Une pression lance tout l’exercice. Le son marque le début et la fin."),
        "it-IT": (["Appoggia il telefono"], "Un tocco avvia tutto l’esercizio. Il suono segna inizio e fine."),
    },
    "04-summary": {
        "en-US": (["Facts, not guesses"], "Every set as it ran — and your addition for next time."),
        "ru-RU": (["Факты, а не догадки"], "Каждый подход как был — и прибавка на следующий раз."),
        "es-ES": (["Hechos, no suposiciones"], "Cada serie como fue — y tu añadido para la próxima."),
        "pt-BR": (["Fatos, não suposições"], "Cada série como foi — seu acréscimo para a próxima."),
        "de-DE": (["Fakten,", "keine Vermutungen"], "Jeder Satz, wie er lief – die Zugabe fürs nächste Mal."),
        "fr-FR": (["Des faits,", "pas des suppositions"], "Chaque série réelle — et ton ajout pour la prochaine fois."),
        "it-IT": (["Fatti, non ipotesi"], "Ogni serie come è andata – e l’aggiunta per la prossima volta."),
    },
    # The work screen: "Skip this set" under Done, "≈ N min left" above.
    "05-skip": {
        "en-US": (["Too much today?"], "Skip a set while you are doing it. The clock follows."),
        "ru-RU": (["Сегодня многовато?"], "Пропусти подход прямо по ходу. Время пересчитается."),
        "es-ES": (["¿Hoy es demasiado?"], "Omite una serie mientras entrenas. El tiempo se ajusta solo."),
        "pt-BR": (["Hoje é demais?"], "Pule uma série durante o treino. O tempo se recalcula."),
        "de-DE": (["Heute zu viel?"], "Überspringe einen Satz mitten im Training – die Zeit passt sich an."),
        "fr-FR": (["Trop pour aujourd’hui" + NNBSP + "?"], "Passe une série en pleine séance. Le temps se recalcule."),
        "it-IT": (["Oggi è troppo?"], "Salta una serie durante l’allenamento: il tempo si ricalcola."),
    },
    "06-progress": {
        "en-US": (["Progress you can see"], "Every movement, step by step."),
        "ru-RU": (["Прогресс,", "который видно"], "Каждое движение, ступень за ступенью."),
        "es-ES": (["Progreso que puedes ver"], "Cada movimiento, paso a paso."),
        "pt-BR": (["Progresso que você vê"], "Cada movimento, passo a passo."),
        "de-DE": (["Fortschritt,", "den du siehst"], "Jede Bewegung, Stufe für Stufe."),
        "fr-FR": (["Une progression visible"], "Chaque mouvement, cran après cran."),
        "it-IT": (["Progressi che", "si vedono"], "Ogni movimento, un gradino alla volta."),
    },
    # New for Play: the home-screen widget — one widget whose layout follows
    # its size (TodayStatusWidget.kt): the day, then the week, then the plan.
    # Worded for any day: WidgetScreenshots rests on Wednesdays and Sundays,
    # so the frame can show "Rest day" as well as "Workout N".
    "07-widget": {
        "en-US": (["On your home screen"], "The day, your week and the plan at a glance."),
        "ru-RU": (["На главном экране"], "День, неделя и план — все на виду."),
        "es-ES": (["En tu pantalla", "de inicio"], "El día, tu semana y el plan, de un vistazo."),
        "pt-BR": (["Na tela inicial"], "O dia, sua semana e o plano num relance."),
        "de-DE": (["Auf dem", "Startbildschirm"], "Der Tag, deine Woche und der Plan – auf einen Blick."),
        "fr-FR": (["Sur l’écran d’accueil"], "La journée, ta semaine et le plan d’un coup d’œil."),
        "it-IT": (["Nella schermata Home"], "La giornata, la settimana e il piano a colpo d’occhio."),
    },
    # The number IS the section count of HowItWorksView.kt (twelve, as on iOS).
    "08-howitworks": {
        "en-US": (["No black box"], "Twelve plain facts about how the plan moves."),
        "ru-RU": (["Без черного ящика"], "Двенадцать простых фактов о том, как движется план."),
        "es-ES": (["Sin caja negra"], "Doce datos claros sobre cómo se mueve el plan."),
        "pt-BR": (["Sem caixa preta"], "Doze fatos simples sobre como o plano se move."),
        "de-DE": (["Keine Blackbox"], "Zwölf einfache Fakten darüber, wie der Plan sich bewegt."),
        "fr-FR": (["Pas de boîte noire"], "Douze faits simples sur le régulateur."),
        "it-IT": (["Niente scatola nera"], "Dodici fatti semplici su come si muove il piano."),
    },
}
