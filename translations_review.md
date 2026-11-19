# 0.21 版本词条修复确认

构建被 `tools/translations.sh` 拦下：42 个新键（扩图功能 + rail 改动）缺 fr/de/es/it/ja/zh-Hans 六语翻译，另有 38 条既有译文排版不合各语言规范。本文档用于逐批确认。

## 进度

- [x] 排版修复 38 条（fr 19 / de 1 / it 15 / zh-Hans 3）——机械性替换（空格类型与引号），已应用，待抽查确认
- [x] 第 1 批（键 1–6）已确认并写入词表
- [x] 第 2 批（键 7–12）已确认并写入词表
- [x] 第 3 批（键 13–18）已确认并写入词表
- [x] 第 4 批（键 19–24）已确认并写入词表
- [x] 第 5 批（键 25–30）已确认并写入词表
- [x] 第 6 批（键 31–36）已确认并写入词表
- [x] 第 7 批（最终批，键 37–42）已确认并写入词表
- [x] 新键译文 42 键 × 6 语，分 7 批（每批 6 键），逐批确认后写入词表（252 值全部写入，校验通过：缺失 0、排版违规 0）

> 显示约定：`␣NBSP` = 不换行空格 U+00A0（法语冒号前）；`·THIN` = 窄空格 U+202F（法语 `; ? !` 前与 « » 内）。

## A. 排版修复 38 条（已应用）

| # | 语言 | 修前 | 修后 |
|---|---|---|---|
| 1 | fr | %@ n’a pas de parcours d’extension : une extension demande un modèle qui édite par référence (Qwen-Image-2.1). | %@ n’a pas de parcours d’extension␣NBSP: une extension demande un modèle qui édite par référence (Qwen-Image-2.1). |
| 2 | fr | Faire grandir la toile vers l’extérieur : quatre pourcentages, sans masque | Faire grandir la toile vers l’extérieur␣NBSP: quatre pourcentages, sans masque |
| 3 | fr | Faites grandir la toile vers l’extérieur : le modèle dessine la nouvelle bordure, et l’original est reposé à l’intérieur. | Faites grandir la toile vers l’extérieur␣NBSP: le modèle dessine la nouvelle bordure, et l’original est reposé à l’intérieur. |
| 4 | fr | Joignez d’abord une image : la toile grandit autour d’elle. | Joignez d’abord une image␣NBSP: la toile grandit autour d’elle. |
| 5 | fr | La toile grandit de pourcentages des côtés de l’image elle-même ; le modèle dessine la nouvelle bordure | La toile grandit de pourcentages des côtés de l’image elle-même·THIN; le modèle dessine la nouvelle bordure |
| 6 | fr | Le préréglage d’extension agrandit la toile — il n’a pas de masque : éteignez la carte, ou retirez le masque. | Le préréglage d’extension agrandit la toile — il n’a pas de masque␣NBSP: éteignez la carte, ou retirez le masque. |
| 7 | fr | Les pourcentages dont chaque côté grandit : des côtés de l’image elle-même, 0–200 | Les pourcentages dont chaque côté grandit␣NBSP: des côtés de l’image elle-même, 0–200 |
| 8 | fr | Les préréglages retirer et redessiner appartiennent au masque : éteignez-les pour étendre. | Les préréglages retirer et redessiner appartiennent au masque␣NBSP: éteignez-les pour étendre. |
| 9 | fr | L’image 1 a changé : retirez l’extension et validez les marges à nouveau. | L’image 1 a changé␣NBSP: retirez l’extension et validez les marges à nouveau. |
| 10 | fr | Rouvrir les marges : ce que vous validez les remplace | Rouvrir les marges␣NBSP: ce que vous validez les remplace |
| 11 | fr | Sans masque : quatre pourcentages — la toile grandit vers l’extérieur, l’original reposé à l’intérieur. | Sans masque␣NBSP: quatre pourcentages — la toile grandit vers l’extérieur, l’original reposé à l’intérieur. |
| 12 | fr | Un masque et une extension éditent de deux façons : retirez d’abord le masque | Un masque et une extension éditent de deux façons␣NBSP: retirez d’abord le masque |
| 13 | fr | Un masque remplace une région, une extension agrandit la toile : retirez l’un des deux. | Un masque remplace une région, une extension agrandit la toile␣NBSP: retirez l’un des deux. |
| 14 | fr | Une extension reste sur ce Mac : arrêtez d’abord de suivre un autre Mac. | Une extension reste sur ce Mac␣NBSP: arrêtez d’abord de suivre un autre Mac. |
| 15 | fr | Une extension édite l’image 1 seule : le texte cite un sujet nommé — retirez le @nom ou l’extension. | Une extension édite l’image 1 seule␣NBSP: le texte cite un sujet nommé — retirez le @nom ou l’extension. |
| 16 | fr | Une extension édite l’image 1 seule : retirez les autres images. | Une extension édite l’image 1 seule␣NBSP: retirez les autres images. |
| 17 | fr | Vérifiez la connexion et recommencez : les fichiers déjà téléchargés sont gardés, celui qui était interrompu recommence. Si huggingface.co reste inaccessible, choisissez une autre source de téléchargement dans le panneau Modèles — ModelScope, ou le miroir. | Vérifiez la connexion et recommencez␣NBSP: les fichiers déjà téléchargés sont gardés, celui qui était interrompu recommence. Si huggingface.co reste inaccessible, choisissez une autre source de téléchargement dans le panneau Modèles — ModelScope, ou le miroir. |
| 18 | fr | Vérifiez que huggingface.co s’ouvre dans un navigateur sur ce Mac — un proxy, un VPN ou un pare-feu peut le refuser — ou choisissez une autre source de téléchargement dans le panneau Modèles (ModelScope, un miroir), puis relancez l’installation : les fichiers déjà téléchargés sont gardés. | Vérifiez que huggingface.co s’ouvre dans un navigateur sur ce Mac — un proxy, un VPN ou un pare-feu peut le refuser — ou choisissez une autre source de téléchargement dans le panneau Modèles (ModelScope, un miroir), puis relancez l’installation␣NBSP: les fichiers déjà téléchargés sont gardés. |
| 19 | fr | « Préréglage extension (0.7) » | «·THINPréréglage extension (0.7)·THIN» |
| 20 | de | Wo die Modelle herkommen. «Automatisch» fragt zuerst huggingface.co, dann ModelScope (魔搭), dann einen Spiegel, und behält den ersten, der antwortet – der Picker sagt vor dem ersten Download, welcher es ist. Jede Datei wird, gleich welcher Quelle, gegen ihre feste sha256 geprüft. | Wo die Modelle herkommen. „Automatisch“ fragt zuerst huggingface.co, dann ModelScope (魔搭), dann einen Spiegel, und behält den ersten, der antwortet – der Picker sagt vor dem ersten Download, welcher es ist. Jede Datei wird, gleich welcher Quelle, gegen ihre feste sha256 geprüft. |
| 21 | it | %@ non ha un flusso di espansione: un'espansione richiede un modello che modifica per riferimento (Qwen-Image-2.1). | %@ non ha un flusso di espansione: un’espansione richiede un modello che modifica per riferimento (Qwen-Image-2.1). |
| 22 | it | Allega prima un'immagine: la tela cresce attorno a essa. | Allega prima un’immagine: la tela cresce attorno a essa. |
| 23 | it | Fai crescere la tela verso l'esterno: il modello disegna il nuovo bordo e l'originale viene rimesso al suo interno. | Fai crescere la tela verso l’esterno: il modello disegna il nuovo bordo e l’originale viene rimesso al suo interno. |
| 24 | it | Fai crescere la tela verso l'esterno: quattro percentuali, nessuna maschera | Fai crescere la tela verso l’esterno: quattro percentuali, nessuna maschera |
| 25 | it | L'immagine 1 è cambiata: rimuovi l'espansione e conferma di nuovo i margini. | L’immagine 1 è cambiata: rimuovi l’espansione e conferma di nuovo i margini. |
| 26 | it | L'immagine, la tela in cui si trova, poi la dimensione che avrà il render | L’immagine, la tela in cui si trova, poi la dimensione che avrà il render |
| 27 | it | La tela cresce di percentuali dei lati dell'immagine stessa; il modello disegna il nuovo bordo | La tela cresce di percentuali dei lati dell’immagine stessa; il modello disegna il nuovo bordo |
| 28 | it | Le percentuali di cui cresce ogni lato: dei lati dell'immagine stessa, 0–200 | Le percentuali di cui cresce ogni lato: dei lati dell’immagine stessa, 0–200 |
| 29 | it | Nessuna maschera: quattro percentuali — la tela cresce verso l'esterno e l'originale viene rimesso al suo interno. | Nessuna maschera: quattro percentuali — la tela cresce verso l’esterno e l’originale viene rimesso al suo interno. |
| 30 | it | Un'espansione modifica solo l'immagine 1: il testo cita un soggetto nominato — rimuovi il @nome o l'espansione. | Un’espansione modifica solo l’immagine 1: il testo cita un soggetto nominato — rimuovi il @nome o l’espansione. |
| 31 | it | Un'espansione modifica solo l'immagine 1: rimuovi le altre immagini. | Un’espansione modifica solo l’immagine 1: rimuovi le altre immagini. |
| 32 | it | Un'espansione resta su questo Mac: smetti prima di seguire un altro Mac. | Un’espansione resta su questo Mac: smetti prima di seguire un altro Mac. |
| 33 | it | Un'espansione richiede un modello che modifica per riferimento (Qwen-Image-2.1), solo l'immagine 1 | Un’espansione richiede un modello che modifica per riferimento (Qwen-Image-2.1), solo l’immagine 1 |
| 34 | it | Una maschera e un'espansione modificano in due modi: rimuovi prima la maschera | Una maschera e un’espansione modificano in due modi: rimuovi prima la maschera |
| 35 | it | Una maschera sostituisce una regione e un'espansione ingrandisce la tela: rimuovine una delle due. | Una maschera sostituisce una regione e un’espansione ingrandisce la tela: rimuovine una delle due. |
| 36 | zh-Hans | 模型的下载来源。「自动」会先询问 huggingface.co，再问魔搭（ModelScope），再问镜像，并记住第一个应答的——在第一次下载之前，选择器就会显示用的是哪个。无论来源是什么，每个文件都会按固定的 sha256 校验。 | 模型的下载来源。“自动”会先询问 huggingface.co，再问魔搭（ModelScope），再问镜像，并记住第一个应答的——在第一次下载之前，选择器就会显示用的是哪个。无论来源是什么，每个文件都会按固定的 sha256 校验。 |
| 37 | zh-Hans | 请在这台 Mac 的浏览器里确认 huggingface.co 能否打开（代理、VPN 或防火墙可能会拒绝），或在「模型」面板里换一个下载源（魔搭、镜像），然后重新安装：已下载的文件会保留。 | 请在这台 Mac 的浏览器里确认 huggingface.co 能否打开（代理、VPN 或防火墙可能会拒绝），或在“模型”面板里换一个下载源（魔搭、镜像），然后重新安装：已下载的文件会保留。 |
| 38 | zh-Hans | 请检查网络连接后重新开始：已下载的文件会保留，被中断的那个会从头再来。如果 huggingface.co 一直无法访问，请在「模型」面板里换一个下载源——魔搭或镜像。 | 请检查网络连接后重新开始：已下载的文件会保留，被中断的那个会从头再来。如果 huggingface.co 一直无法访问，请在“模型”面板里换一个下载源——魔搭或镜像。 |

## B. 新键译文（42 键 × 6 语）

（分批填写，逐批确认；确认后写入词表并更新进度。以下翻译里 fr 冒号前为 NBSP、« » 内为窄空格，均为真实字符。）

### 第 1 批（键 1–6）：CLI 参数校验消息

**1. `%@ expects %lld to %lld, a multiple of 128, not "%@"`**（en 为位置式 `%1$@ expects %2$lld to %3$lld, a multiple of 128, not "%4$@"`）

- fr: `%1$@ attend %2$lld à %3$lld, un multiple de 128, pas «\u202f%4$@\u202f»`
- de: `%1$@ erwartet %2$lld bis %3$lld, ein Vielfaches von 128, nicht „%4$@“`
- es: `%1$@ espera %2$lld a %3$lld, un múltiplo de 128, no «%4$@»`
- it: `%1$@ richiede da %2$lld a %3$lld, un multiplo di 128, non «%4$@»`
- ja: `%1$@ は %2$lld〜%3$lld の範囲で、128 の倍数を指定してください。「%4$@」は指定できません`
- zh-Hans: `%1$@ 需要 %2$lld 至 %3$lld，且为 128 的倍数，而不是“%4$@”`

**2. `%@ takes no reference block of the kind the expand’s canvas needs (--mode expand)`**

- fr: `%1$@ n’accepte pas de bloc de référence du type qu’exige la toile de l’extension (--mode expand)`
- de: `%1$@ nimmt keinen Referenzblock der Art, die die Leinwand des Erweiterns braucht (--mode expand)`
- es: `%1$@ no acepta un bloque de referencia del tipo que necesita el lienzo de la ampliación (--mode expand)`
- it: `%1$@ non accetta un blocco di riferimento del tipo che richiede la tela dell’espansione (--mode expand)`
- ja: `%1$@ は、拡張のキャンバスが必要とする種類の参照ブロックを受け付けません（--mode expand）`
- zh-Hans: `%1$@ 不接受扩图画布所需类型的参考块（--mode expand）`

**3. `%@ × %@`**

- fr: `%1$@ × %2$@`
- de: `%1$@ × %2$@`
- es: `%1$@ × %2$@`
- it: `%1$@ × %2$@`
- ja: `%1$@ × %2$@`
- zh-Hans: `%1$@ × %2$@`

**4. `--expand and --max-side go with --mask: the expand’s pads are --pad`**

- fr: `--expand et --max-side vont avec --mask␣: les marges de l’extension sont --pad`
- de: `--expand und --max-side gehören zu --mask: die Ränder des Erweiterns sind --pad`
- es: `--expand y --max-side van con --mask: los márgenes de la ampliación son --pad`
- it: `--expand e --max-side vanno con --mask: i margini dell’espansione sono --pad`
- ja: `--expand と --max-side は --mask と一緒に使います。拡張の余白は --pad です`
- zh-Hans: `--expand 与 --max-side 需配合 --mask 使用：扩图的外扩是 --pad`

**5. `--lora expand goes alone: remove and redraw are the mask’s branches`**

- fr: `--lora expand va seul␣: remove et redraw sont les branches du masque`
- de: `--lora expand geht allein: remove und redraw sind die Zweige der Maske`
- es: `--lora expand va solo: remove y redraw son las ramas de la máscara`
- it: `--lora expand va da solo: remove e redraw sono i rami della maschera`
- ja: `--lora expand は単独で使います。remove と redraw はマスクの分岐です`
- zh-Hans: `--lora expand 需单独使用：remove 和 redraw 是遮罩的分支`

**6. `--mode expand and --mask don’t go together: the mask’s region is replaced, the expand’s canvas keeps the image`**

- fr: `--mode expand et --mask ne vont pas ensemble␣: la région du masque est remplacée, la toile de l’extension garde l’image`
- de: `--mode expand und --mask passen nicht zusammen: die Region der Maske wird ersetzt, die Leinwand des Erweiterns behält das Bild`
- es: `--mode expand y --mask no van juntos: la región de la máscara se reemplaza, el lienzo de la ampliación conserva la imagen`
- it: `--mode expand e --mask non vanno insieme: la regione della maschera è sostituita, la tela dell’espansione conserva l’immagine`
- ja: `--mode expand と --mask は併用できません。マスクの領域は置き換えられますが、拡張のキャンバスは画像を保ちます`
- zh-Hans: `--mode expand 与 --mask 不能同时使用：遮罩替换区域，扩图画布保留原图`

### 第 2 批（键 7–12）：CLI 参数校验消息（续）

**7. `--mode expand contradicts --lora %@`**

- fr: `--mode expand contredit --lora %@`
- de: `--mode expand widerspricht --lora %@`
- es: `--mode expand contradice --lora %@`
- it: `--mode expand contraddice --lora %@`
- ja: `--mode expand は --lora %@ と矛盾します`
- zh-Hans: `--mode expand 与 --lora %@ 相互矛盾`

**8. `--mode remove (the default), redraw — or expand, the canvas that grows — silicontrol help add`**

- fr: `--mode remove (par défaut), redraw — ou expand, la toile qui grandit — silicontrol help add`
- de: `--mode remove (die Voreinstellung), redraw – oder expand, die Leinwand, die wächst – silicontrol help add`（德语破折号用 en dash –）
- es: `--mode remove (por defecto), redraw — o expand, el lienzo que crece — silicontrol help add`
- it: `--mode remove (predefinita), redraw — oppure expand, la tela che cresce — silicontrol help add`
- ja: `--mode remove（デフォルト）、redraw — または expand、広がるキャンバス — silicontrol help add`
- zh-Hans: `--mode remove（默认）、redraw —— 或 expand，向外生长的画布 —— silicontrol help add`

**9. `--pad and --max-sample go with --mode expand: the canvas’s pads and sampling ceiling`**

- fr: `--pad et --max-sample vont avec --mode expand␣: les marges de la toile et le plafond d’échantillonnage`
- de: `--pad und --max-sample gehören zu --mode expand: die Ränder der Leinwand und die Obergrenze des Samplings`
- es: `--pad y --max-sample van con --mode expand: los márgenes del lienzo y el techo de muestreo`
- it: `--pad e --max-sample vanno con --mode expand: i margini della tela e il tetto del campionamento`
- ja: `--pad と --max-sample は --mode expand と一緒に使います。キャンバスの余白とサンプリングの上限です`
- zh-Hans: `--pad 与 --max-sample 需配合 --mode expand 使用：画布的外扩与采样上限`

**10. `--pad and --max-sample go with --mode expand: the mask decides its own crop`**

- fr: `--pad et --max-sample vont avec --mode expand␣: le masque décide de sa propre découpe`
- de: `--pad und --max-sample gehören zu --mode expand: die Maske entscheidet über ihren eigenen Ausschnitt`
- es: `--pad y --max-sample van con --mode expand: la máscara decide su propio recorte`
- it: `--pad e --max-sample vanno con --mode expand: la maschera decide il proprio ritaglio`
- ja: `--pad と --max-sample は --mode expand と一緒に使います。マスクは自分自身の切り出しを決めます`
- zh-Hans: `--pad 与 --max-sample 需配合 --mode expand 使用：遮罩自行决定裁剪区域`

**11. `--pad expects four percents from 0 to 200, left,right,top,bottom, not "%@"`**

- fr: `--pad attend quatre pourcentages de 0 à 200, left,right,top,bottom, pas «\u202f%@\u202f»`
- de: `--pad erwartet vier Prozente von 0 bis 200, left,right,top,bottom, nicht „%@“`
- es: `--pad espera cuatro porcentajes de 0 a 200, left,right,top,bottom, no «%@»`
- it: `--pad richiede quattro percentuali da 0 a 200, left,right,top,bottom, non «%@»`
- ja: `--pad には 0〜200 の割合を 4 つ、left,right,top,bottom の順で指定してください。「%@」は指定できません`
- zh-Hans: `--pad 需要四个 0 到 200 的百分比，按 left,right,top,bottom 的顺序，而不是“%@”`

**12. `--ref and --mode expand don’t go together: the canvas is the edit’s only image`**

- fr: `--ref et --mode expand ne vont pas ensemble␣: la toile est la seule image de l’édition`
- de: `--ref und --mode expand passen nicht zusammen: die Leinwand ist das einzige Bild der Bearbeitung`
- es: `--ref y --mode expand no van juntos: el lienzo es la única imagen de la edición`
- it: `--ref e --mode expand non vanno insieme: la tela è l’unica immagine della modifica`
- ja: `--ref と --mode expand は併用できません。キャンバスが編集で使う唯一の画像です`
- zh-Hans: `--ref 与 --mode expand 不能同时使用：画布就是编辑时唯一的图像`

### 第 3 批（键 13–18）：扩图参数消息 + 编辑器 UI

**13. `--strength and --mode expand don’t go together: the expand starts from noise`**

- fr: `--strength et --mode expand ne vont pas ensemble␣: l’extension part du bruit`
- de: `--strength und --mode expand passen nicht zusammen: das Erweitern beginnt mit Rauschen`
- es: `--strength y --mode expand no van juntos: la ampliación parte del ruido`
- it: `--strength e --mode expand non vanno insieme: l’espansione parte dal rumore`
- ja: `--strength と --mode expand は併用できません。拡張はノイズから始まります`
- zh-Hans: `--strength 与 --mode expand 不能同时使用：扩图从噪声开始`

**14. `All four pads are 0: give at least one side a percent to grow by.`**

- fr: `Les quatre marges sont à 0␣: donnez à au moins un côté un pourcentage pour grandir.`
- de: `Alle vier Ränder sind 0: gib mindestens einer Seite einen Prozentsatz zum Wachsen.`
- es: `Los cuatro márgenes son 0: dale a al menos un lado un porcentaje para crecer.`
- it: `Tutti e quattro i margini sono 0: dai ad almeno un lato una percentuale per crescere.`
- ja: `余白がすべて 0 です。いずれかの辺に広げる割合を指定してください。`
- zh-Hans: `四个外扩都是 0：请至少给一条边一个生长的百分比。`

**15. `Center the canvas to %lld:%lld`**（en 为位置式 `Center the canvas to %1$lld:%2$lld`）

- fr: `Centrer la toile sur %1$lld:%2$lld`
- de: `Die Leinwand auf %1$lld:%2$lld zentrieren`
- es: `Centrar el lienzo en %1$lld:%2$lld`
- it: `Centra la tela su %1$lld:%2$lld`
- ja: `キャンバスを %1$lld:%2$lld に合わせる`
- zh-Hans: `将画布居中为 %1$lld:%2$lld`

**16. `Expand: drag the handles to grow the canvas, then expand`**

- fr: `Étendre␣: tirez les poignées pour faire grandir la toile, puis étendez`（fr 用 vous，与词表一致）
- de: `Erweitern: ziehe die Griffe, um die Leinwand wachsen zu lassen, und erweitere dann`（de 用 du，与「Lege die Ränder an」一致）
- es: `Ampliar: arrastra los tiradores para hacer crecer el lienzo, y luego amplía`
- it: `Espandi: trascina le maniglie per far crescere la tela, poi espandi`
- ja: `拡張：ハンドルをドラッグしてキャンバスを広げ、拡張します`
- zh-Hans: `扩图：拖动手柄扩大画布，然后扩图`

**17. `Fold the Rack`**

- fr: `Replier le rack`
- de: `Rack einklappen`
- es: `Plegar el rack`
- it: `Chiudi il rack`
- ja: `ラックを畳む`
- zh-Hans: `收起机架`

**18. `Fold the rack: the model picker alone`**（picker 术语已从词表核对：de der Picker / ja ピッカー / es el selector）

- fr: `Replier le rack␣: le sélecteur de modèle seul`
- de: `Rack einklappen: nur der Picker`
- es: `Plegar el rack: solo el selector`
- it: `Chiudi il rack: solo il selettore`
- ja: `ラックを畳む：モデルのピッカーだけ`
- zh-Hans: `收起机架：只留下模型选择器`

### 第 4 批（键 19–24）：菜单命令 + 编辑器工具提示

**19. `Import Images…`**（与既有 `Import a Model or LoRA…` 各语风格核对：de 省略号前留空格，其余不留）

- fr: `Importer des images…`
- de: `Bilder importieren …`
- es: `Importar imágenes…`
- it: `Importa immagini…`
- ja: `画像を読み込む…`（ja 用「読み込む」，与既有导入命令一致）
- zh-Hans: `导入图像…`

**20. `Keep the handles' proportions`**（菜单命令：fr/de/es 用不定式，it 用第二人称命令式，与既有菜单一致）

- fr: `Conserver les proportions des poignées`
- de: `Die Proportionen der Griffe beibehalten`
- es: `Mantener las proporciones de los tiradores`
- it: `Mantieni le proporzioni delle maniglie`
- ja: `ハンドルの比率を保つ`
- zh-Hans: `保持手柄的比例`

**21. `Leave without the pads (Esc)`**（Esc 写法与既有 `(Échap)`/`(Esc)`/`（Esc）` 一致）

- fr: `Quitter sans les marges (Échap)`
- de: `Ohne die Ränder schließen (Esc)`
- es: `Salir sin los márgenes (Esc)`
- it: `Chiudi senza i margini (Esc)`
- ja: `余白を破棄して閉じる（Esc）`
- zh-Hans: `放弃外扩并关闭（Esc）`

**22. `Open images from the Finder: they go to the Prompt Lab, ready to be edited`**

- fr: `Ouvrez des images depuis le Finder␣: elles vont à l’atelier, prêtes à être modifiées`（fr 的 Prompt Lab = l’atelier，已核对）
- de: `Öffne Bilder aus dem Finder: sie gehen ins Prompt-Labor und sind bereit zur Bearbeitung`
- es: `Abre imágenes desde el Finder: van al laboratorio de prompts, listas para editarse`
- it: `Apri immagini dal Finder: vanno al laboratorio dei prompt, pronte per essere modificate`
- ja: `Finder から画像を開くと、プロンプトラボに入り、すぐ編集できます`
- zh-Hans: `从访达打开的图像会进入提示词实验室，随时可以编辑`

**23. `Paint the mask: paint on the image, leave the tool to use it`**（画笔工具的帮助：笔触即遮罩，离开工具时启用）

- fr: `Peignez le masque␣: peignez sur l’image, puis quittez l’outil pour l’appliquer`
- de: `Maske malen: male auf das Bild, verlasse das Werkzeug, um sie zu benutzen`
- es: `Pinta la máscara: pinta sobre la imagen, y deja la herramienta para usarla`
- it: `Dipingi la maschera: dipingi sull’immagine, lascia lo strumento per usarla`
- ja: `マスクを描く：画像に描き、ツールを離すと使用されます`
- zh-Hans: `绘制遮罩：在图像上涂抹，收起工具后即会使用`

**24. `Pan and zoom (drag, pinch, double-click to fit)`**（pinch 术语与既有词条一致：pincer / Zwei-Finger-Zoom / pellizcar / pizzica / ピンチ / 双指缩放）

- fr: `Panoramique et zoom (glisser, pincer, double-clic pour tout afficher)`
- de: `Verschieben und Zoomen (ziehen, Zwei-Finger-Zoom, Doppelklick zum Anpassen)`
- es: `Desplazar y hacer zoom (arrastrar, pellizcar, doble clic para ajustar)`
- it: `Panoramica e zoom (trascina, pizzica, doppio clic per adattare)`
- ja: `パンとズーム（ドラッグ、ピンチ、ダブルクリックで合わせる）`
- zh-Hans: `平移与缩放（拖动、双指缩放、双击适应窗口）`

### 第 5 批（键 25–30）：扩图编辑器标签与机架

**25. `The canvas`**（扩图编辑器读数里的画布尺寸标签）

- fr: `La toile`
- de: `Die Leinwand`
- es: `El lienzo`
- it: `La tela`
- ja: `キャンバス`
- zh-Hans: `画布`

**26. `The canvas cannot be this shape: give a side a percent to grow by`**

- fr: `La toile ne peut pas prendre cette forme␣: donnez à un côté un pourcentage pour grandir`
- de: `Die Leinwand kann diese Form nicht haben: gib einer Seite einen Prozentsatz zum Wachsen`
- es: `El lienzo no puede tener esta forma: dale a un lado un porcentaje para crecer`
- it: `La tela non può avere questa forma: dai a un lato una percentuale per crescere`
- ja: `キャンバスをこの形にはできません。いずれかの辺に広げる割合を指定してください`
- zh-Hans: `画布不能是这个形状：请给一条边一个生长的百分比`

**27. `The pads go to the workflow: « Generate » says « Expand »`**（box 术语已核对：fr la boîte / de der Kasten / es la caja / it la casella / ja ボックス / zh 方框）

- fr: `Les marges vont au parcours␣: «·Générer·» dit «·Étendre·»`
- de: `Die Ränder gehen in den Ablauf: „Generieren“ sagt „Erweitern“`
- es: `Los márgenes van al flujo: «Generar» dice «Ampliar»`
- it: `I margini vanno al flusso: «Genera» dice «Espandi»`
- ja: `余白は手順に渡ります。「生成」は「拡張」と表示します`
- zh-Hans: `外扩交给流程：“生成”会变成“扩图”`

**28. `The render`**（扩图编辑器读数里的渲染尺寸标签；"the render" 名词已核对：fr Le rendu / de Das Rendern / es El renderizado / it Il rendering / ja レンダリング / zh 渲染）

- fr: `Le rendu`
- de: `Das Rendern`
- es: `El renderizado`
- it: `Il rendering`
- ja: `レンダリング`
- zh-Hans: `渲染`

**29. `Unfold the Rack`**

- fr: `Déplier le rack`
- de: `Rack ausklappen`
- es: `Desplegar el rack`
- it: `Apri il rack`
- ja: `ラックを広げる`
- zh-Hans: `展开机架`

**30. `Unfold the rack: the chain, its boxes and « Generate »`**

- fr: `Déplier le rack␣: la chaîne, ses boîtes et «·Générer·»`
- de: `Rack ausklappen: die Kette, seine Kästen und „Generieren“`
- es: `Desplegar el rack: la cadena, sus cajas y «Generar»`
- it: `Apri il rack: la catena, le sue caselle e «Genera»`
- ja: `ラックを広げる：チェーン、そのボックス、そして「生成」`
- zh-Hans: `展开机架：处理链、各个方框和“生成”`

### 第 6 批（键 31–36）：缩放菜单 + CLI 参数修复建议

**31. `Zoom In (⌘+)`**（沿用既有 Zoom In/Out/Zoom to Fit 译文，仅加快捷键；括号风格与词表一致：fr/de/es/it 半角、ja/zh 全角）

- fr: `Zoom avant (⌘+)`
- de: `Vergrößern (⌘+)`
- es: `Ampliar (⌘+)`
- it: `Ingrandisci (⌘+)`
- ja: `拡大（⌘+）`
- zh-Hans: `放大（⌘+）`

**32. `Zoom Out (⌘−)`**

- fr: `Zoom arrière (⌘−)`
- de: `Verkleinern (⌘−)`
- es: `Reducir (⌘−)`
- it: `Riduci (⌘−)`
- ja: `縮小（⌘−）`
- zh-Hans: `缩小（⌘−）`

**33. `Zoom to Fit (⌘0)`**

- fr: `Taille ajustée (⌘0)`
- de: `Größe anpassen (⌘0)`
- es: `Ajustar a la ventana (⌘0)`
- it: `Adatta alla finestra (⌘0)`
- ja: `ウインドウに合わせる（⌘0）`
- zh-Hans: `适合窗口大小（⌘0）`

**34. `drop --mask, or leave --pad out`**

- fr: `retirez --mask, ou laissez --pad de côté`
- de: `lasse --mask weg, oder lass --pad weg`
- es: `quita --mask, o deja --pad fuera`
- it: `rimuovi --mask, o lascia --pad fuori`
- ja: `--mask を外すか、--pad を省いてください`
- zh-Hans: `去掉 --mask，或省略 --pad`

**35. `drop --mask: --image is the image the canvas grows from`**

- fr: `retirez --mask␣: --image est l’image dont la toile grandit`
- de: `lasse --mask weg: --image ist das Bild, von dem die Leinwand wächst`
- es: `quita --mask: --image es la imagen de la que crece el lienzo`
- it: `rimuovi --mask: --image è l’immagine da cui cresce la tela`
- ja: `--mask を外してください。--image はキャンバスが広がる元の画像です`
- zh-Hans: `去掉 --mask：--image 是画布向外生长的原图`

**36. `grid does not take --mode expand`**（与既有的 "takes no reference block" 译文动词一致：n’accepte pas / nimmt kein / no acepta / non accetta / 受け付けません / 不接受）

- fr: `grid n’accepte pas --mode expand`
- de: `grid nimmt kein --mode expand`
- es: `grid no acepta --mode expand`
- it: `grid non accetta --mode expand`
- ja: `grid は --mode expand を受け付けません`
- zh-Hans: `grid 不接受 --mode expand`

### 第 7 批（最终批，键 37–42）：剩余 CLI 键

> 说明：核对词表发现原计划第 2 批有两条 CLI 键（`--mode expand goes with --image…`、`--mode expects remove…`）实际未写入草稿文件（已确认的 6 批与词表内容一致，无出入），连同 4 条收尾键合并为本批。

**37. `--mode expand goes with --image <the image the canvas grows from>`**

- fr: `--mode expand va avec --image <l’image dont la toile grandit>`
- de: `--mode expand gehört zu --image <das Bild, von dem die Leinwand wächst>`
- es: `--mode expand va con --image <la imagen de la que crece el lienzo>`
- it: `--mode expand va con --image <l’immagine da cui cresce la tela>`
- ja: `--mode expand は --image <キャンバスが広がる元の画像> と一緒に使います`
- zh-Hans: `--mode expand 需与 --image <画布向外生长的原图> 一起使用`

**38. `--mode expects remove, redraw or expand, not "%@"`**

- fr: `--mode attend remove, redraw ou expand, pas «·%@·»`
- de: `--mode erwartet remove, redraw oder expand, nicht „%@“`
- es: `--mode espera remove, redraw o expand, no «%@»`
- it: `--mode richiede remove, redraw o expand, non «%@»`
- ja: `--mode には remove、redraw、expand のいずれかを指定してください。「%@」は指定できません`
- zh-Hans: `--mode 需要 remove、redraw 或 expand，而不是“%@”`

**39. `leave --lora out: --mode expand wires its preset`**（preset 术语已核对：fr Préréglage / de Voreinstellung / es Preajuste / it Preimpostazione / ja プリセット / zh 预设）

- fr: `laissez --lora de côté␣: --mode expand choisit son préréglage`
- de: `lasse --lora weg: --mode expand wählt die Voreinstellung selbst`
- es: `deja --lora fuera: --mode expand conecta su preajuste`
- it: `lascia --lora fuori: --mode expand collega la sua preimpostazione`
- ja: `--lora を外してください。--mode expand はプリセットを自動で設定します`
- zh-Hans: `不写 --lora：--mode expand 会自动接上它的预设`

**40. `render one expand with add — silicontrol help add`**

- fr: `faites une extension avec add — silicontrol help add`
- de: `erweitere mit add – silicontrol help add`（de 用 en dash `–`）
- es: `haz una ampliación con add — silicontrol help add`
- it: `fai un’espansione con add — silicontrol help add`
- ja: `add で拡張を一度実行 — silicontrol help add`
- zh-Hans: `用 add 渲染一次扩图 —— silicontrol help add`

**41. `the expand’s canvas decides the format: leave 1024 / WxH out`**

- fr: `la toile de l’extension décide du format␣: laissez 1024 / WxH de côté`
- de: `die Leinwand des Erweiterns entscheidet über das Format: lasse 1024 / WxH weg`
- es: `el lienzo de la ampliación decide el formato: deja 1024 / WxH fuera`
- it: `la tela dell’espansione decide il formato: lascia 1024 / WxH fuori`
- ja: `拡張のキャンバスが形式を決めます。1024 / WxH は省いてください`
- zh-Hans: `扩图画布决定格式：省略 1024 / WxH`

**42. `the expand’s prompt does not cite named subjects yet`**（镜像既有键 "a grid does not cite named subjects yet" 的六语措辞）

- fr: `le prompt de l’extension ne cite pas encore de sujets nommés`
- de: `der Prompt des Erweiterns nennt noch keine benannten Motive`
- es: `el prompt de la ampliación aún no cita sujetos con nombre`
- it: `il prompt dell’espansione non cita ancora soggetti con nome`
- ja: `拡張のプロンプトは名前付きサブジェクトをまだ引用できません`
- zh-Hans: `扩图的提示词暂时还不能引用已命名的主体`

