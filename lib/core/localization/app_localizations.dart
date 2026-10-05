import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/settings_model.dart';

/// Lightweight, type-safe localization dictionary for Phantek Gallery.
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  String get _lang => locale.languageCode;

  // ── Navigation & Tabs ──────────────────────────────────────────────────────
  String get all => _t(
        en: 'All',
        id: 'Semua',
        zh: '全部',
        es: 'Todos',
        pt: 'Todos',
        ja: 'すべて',
        ko: '전체',
        hi: 'सभी',
        ar: 'الكل',
        fr: 'Tous',
        ru: 'Все',
      );

  String get photos => _t(
        en: 'Photos',
        id: 'Foto',
        zh: '照片',
        es: 'Fotos',
        pt: 'Fotos',
        ja: '写真',
        ko: '사진',
        hi: 'फ़ोटो',
        ar: 'الصور',
        fr: 'Photos',
        ru: 'Фото',
      );

  String get videos => _t(
        en: 'Videos',
        id: 'Video',
        zh: '视频',
        es: 'Vídeos',
        pt: 'Vídeos',
        ja: '動画',
        ko: '동영상',
        hi: 'वीडियो',
        ar: 'الفيديوهات',
        fr: 'Vidéos',
        ru: 'Видео',
      );

  String get albums => _t(
        en: 'Albums',
        id: 'Album',
        zh: '相册',
        es: 'Álbumes',
        pt: 'Álbuns',
        ja: 'アルバム',
        ko: '앨범',
        hi: 'एल्बम',
        ar: 'الألبومات',
        fr: 'Albums',
        ru: 'Альбомы',
      );

  String get favorites => _t(
        en: 'Favorites',
        id: 'Favorit',
        zh: '收藏',
        es: 'Favoritos',
        pt: 'Favoritos',
        ja: 'お気に入り',
        ko: '즐겨찾기',
        hi: 'पसंदीदा',
        ar: 'المفضلة',
        fr: 'Favoris',
        ru: 'Избранное',
      );

  // ── Search & Filter ────────────────────────────────────────────────────────
  String get searchHint => _t(
        en: 'Search media or albums...',
        id: 'Cari media atau album...',
        zh: '搜索媒体或相册...',
        es: 'Buscar medios o álbumes...',
        pt: 'Pesquisar mídias ou álbuns...',
        ja: 'メディアまたはアルバムを検索...',
        ko: '미디어 또는 앨범 검색...',
        hi: 'मीडिया या एल्बम खोजें...',
        ar: 'البحث في الوسائط أو الألبومات...',
        fr: 'Rechercher médias ou albums...',
        ru: 'Поиск медиа или альбомов...',
      );

  String get noMediaFound => _t(
        en: 'No media found',
        id: 'Tidak ada media',
        zh: '未找到媒体',
        es: 'No se encontraron medios',
        pt: 'Nenhuma mídia encontrada',
        ja: 'メディアが見つかりません',
        ko: '미디어를 찾을 수 없습니다',
        hi: 'कोई मीडिया नहीं मिला',
        ar: 'لم يتم العثور على وسائط',
        fr: 'Aucun média trouvé',
        ru: 'Медиафайлы не найдены',
      );

  String get selected => _t(
        en: 'selected',
        id: 'dipilih',
        zh: '已选择',
        es: 'seleccionado',
        pt: 'selecionado',
        ja: '選択済み',
        ko: '선택됨',
        hi: 'चयनित',
        ar: 'محدد',
        fr: 'sélectionné',
        ru: 'выбрано',
      );

  // ── Settings Sections ──────────────────────────────────────────────────────
  String get settings => _t(
        en: 'Settings',
        id: 'Pengaturan',
        zh: '设置',
        es: 'Ajustes',
        pt: 'Configurações',
        ja: '設定',
        ko: '설정',
        hi: 'सेटिंग्स',
        ar: 'الإعدادات',
        fr: 'Paramètres',
        ru: 'Настройки',
      );

  String get appearance => _t(
        en: 'Appearance',
        id: 'Tampilan',
        zh: '外观',
        es: 'Apariencia',
        pt: 'Aparência',
        ja: '外観',
        ko: '화면',
        hi: 'रूप-रंग',
        ar: 'المظهر',
        fr: 'Apparence',
        ru: 'Внешний вид',
      );

  String get theme => _t(
        en: 'Theme',
        id: 'Tema',
        zh: '主题',
        es: 'Tema',
        pt: 'Tema',
        ja: 'テーマ',
        ko: '테마',
        hi: 'थीम',
        ar: 'السمة',
        fr: 'Thème',
        ru: 'Тема',
      );

  String get language => _t(
        en: 'Language',
        id: 'Bahasa',
        zh: '语言',
        es: 'Idioma',
        pt: 'Idioma',
        ja: '言語',
        ko: '언어',
        hi: 'भाषा',
        ar: 'اللغة',
        fr: 'Langue',
        ru: 'Язык',
      );

  String get chooseLanguage => _t(
        en: 'Choose Language',
        id: 'Pilih Bahasa',
        zh: '选择语言',
        es: 'Elegir idioma',
        pt: 'Escolher idioma',
        ja: '言語を選択',
        ko: '언어 선택',
        hi: 'भाषा चुनें',
        ar: 'اختر اللغة',
        fr: 'Choisir la langue',
        ru: 'Выберите язык',
      );

  String get gridColumns => _t(
        en: 'Grid Columns',
        id: 'Kolom Grid',
        zh: '网格列数',
        es: 'Columnas de cuadrícula',
        pt: 'Colunas da grade',
        ja: 'グリッド列',
        ko: '그리드 열',
        hi: 'ग्रिड कॉलम',
        ar: 'أعمدة الشبكة',
        fr: 'Colonnes de la grille',
        ru: 'Столбцы сетки',
      );

  String get albumsGridColumns => _t(
        en: 'Albums Grid Columns',
        id: 'Kolom Grid Album',
        zh: '相册网格列数',
        es: 'Columnas de álbumes',
        pt: 'Colunas dos álbuns',
        ja: 'アルバム列',
        ko: '앨범 열',
        hi: 'एल्बम ग्रिड कॉलम',
        ar: 'أعمدة شبكة الألبومات',
        fr: 'Colonnes des albums',
        ru: 'Столбцы сетки альбомов',
      );

  String get showDurationBadges => _t(
        en: 'Show Duration Badges',
        id: 'Tampilkan Durasi',
        zh: '显示时长徽标',
        es: 'Mostrar duración',
        pt: 'Mostrar duração',
        ja: '時間バッジを表示',
        ko: '시간 배지 표시',
        hi: 'अवधि बैज दिखाएं',
        ar: 'إظهار شارات المدة',
        fr: 'Afficher les badges de durée',
        ru: 'Показывать значки длительности',
      );

  String get showDurationBadgesSubtitle => _t(
        en: 'Video duration overlay on thumbnails',
        id: 'Overlay durasi video pada thumbnail',
        zh: '缩略图上叠加视频时长',
        es: 'Superposición de duración en miniaturas',
        pt: 'Duração do vídeo nas miniaturas',
        ja: 'サムネイル上に動画の長さを表示',
        ko: '썸네일에 비디오 길이 표시',
        hi: 'थंबनेल पर वीडियो की अवधि दिखाएं',
        ar: 'تراكب مدة الفيديو على الصور المصغرة',
        fr: 'Durée de la vidéo sur les miniatures',
        ru: 'Длительность видео на миниатюрах',
      );

  String get cache => _t(
        en: 'Cache',
        id: 'Cache',
        zh: '缓存',
        es: 'Caché',
        pt: 'Cache',
        ja: 'キャッシュ',
        ko: '캐시',
        hi: 'कैश',
        ar: 'ذاكرة التخزين المؤقت',
        fr: 'Cache',
        ru: 'Кэш',
      );

  String get clearThumbnailCache => _t(
        en: 'Clear Thumbnail Cache',
        id: 'Hapus Cache Thumbnail',
        zh: '清除缩略图缓存',
        es: 'Limpiar caché de miniaturas',
        pt: 'Limpar cache de miniaturas',
        ja: 'サムネイルキャッシュを削除',
        ko: '썸네일 캐시 지우기',
        hi: 'थंबनेल कैश साफ़ करें',
        ar: 'مسح ذاكرة التخزين المؤقت للصور المصغرة',
        fr: 'Vider le cache des miniatures',
        ru: 'Очистить кэш миниатюр',
      );

  String get playback => _t(
        en: 'Playback',
        id: 'Pemutaran',
        zh: '播放',
        es: 'Reproducción',
        pt: 'Reprodução',
        ja: '再生',
        ko: '재생',
        hi: 'प्लेबैक',
        ar: 'التشغيل',
        fr: 'Lecture',
        ru: 'Воспроизведение',
      );

  String get hardwareAcceleration => _t(
        en: 'Hardware Acceleration',
        id: 'Akselerasi Hardware',
        zh: '硬件加速',
        es: 'Aceleración por hardware',
        pt: 'Aceleração de hardware',
        ja: 'ハードウェアアクセラレーション',
        ko: '하드웨어 가속',
        hi: 'हार्डवेयर त्वरण',
        ar: 'تسريع الأجهزة',
        fr: 'Accélération matérielle',
        ru: 'Аппаратное ускорение',
      );

  String get hardwareAccelerationSubtitle => _t(
        en: 'Direct GPU decoding for smooth playback',
        id: 'Dekode GPU langsung untuk pemutaran mulus',
        zh: '直接GPU解码以实现流畅播放',
        es: 'Decodificación directa por GPU',
        pt: 'Decodificação direta por GPU',
        ja: 'GPUデコードでスムーズな再生',
        ko: '원활한 재생을 위한 직접 GPU 디코딩',
        hi: 'सुचारू प्लेबैक के लिए प्रत्यक्ष GPU डिकोडिंग',
        ar: 'فك تشفير مباشر عبر GPU للتشغيل السلس',
        fr: 'Décodage direct par GPU',
        ru: 'Прямое аппаратное декодирование GPU',
      );

  String get autoPlayVideo => _t(
        en: 'Auto-play Videos',
        id: 'Putar Otomatis Video',
        zh: '自动播放视频',
        es: 'Reproducir vídeos automáticamente',
        pt: 'Reproduzir vídeos automaticamente',
        ja: '動画の自動再生',
        ko: '동영상 자동 재생',
        hi: 'स्वचालित रूप से वीडियो चलाएं',
        ar: 'تشغيل الفيديو تلقائياً',
        fr: 'Lecture automatique des vidéos',
        ru: 'Автовоспроизведение видео',
      );

  String get autoPlayVideoSubtitle => _t(
        en: 'Start playing immediately on open',
        id: 'Langsung memutar video saat dibuka',
        zh: '打开时立即开始播放',
        es: 'Comenzar a reproducir al abrir',
        pt: 'Iniciar reprodução ao abrir',
        ja: '開いたときにすぐに再生を開始',
        ko: '열 때 즉시 재생 시작',
        hi: 'खोलते ही तुरंत प्ले शुरू करें',
        ar: 'بدء التشغيل فور الفتح',
        fr: 'Lancer la lecture immédiatement à l\'ouverture',
        ru: 'Начинать воспроизведение при открытии',
      );

  String get storage => _t(
        en: 'Storage',
        id: 'Penyimpanan',
        zh: '存储',
        es: 'Almacenamiento',
        pt: 'Armazenamento',
        ja: 'ストレージ',
        ko: '저장소',
        hi: 'संग्रहण',
        ar: 'التخزين',
        fr: 'Stockage',
        ru: 'Память',
      );

  String get trashBin => _t(
        en: 'Trash Bin',
        id: 'Tempat Sampah',
        zh: '回收站',
        es: 'Papelera de reciclaje',
        pt: 'Lixeira',
        ja: 'ゴミ箱',
        ko: '휴지통',
        hi: 'रीसायकल बिन',
        ar: 'سلة المهملات',
        fr: 'Corbeille',
        ru: 'Корзина',
      );

  String get trashBinSubtitle => _t(
        en: 'Move to trash instead of deleting',
        id: 'Pindahkan ke sampah bukan menghapus permanen',
        zh: '移至回收站而非永久删除',
        es: 'Mover a la papelera en lugar de eliminar',
        pt: 'Mover para a lixeira em vez de excluir',
        ja: '削除せずにゴミ箱に移動',
        ko: '영구 삭제 대신 휴지통으로 이동',
        hi: 'हटाने के बजाय रीसायकल बिन में ले जाएं',
        ar: 'النقل إلى سلة المهملات بدلاً من الحذف',
        fr: 'Mettre à la corbeille au lieu de supprimer',
        ru: 'Перемещать в корзину вместо удаления',
      );

  String get excludedFolders => _t(
        en: 'Excluded Folders',
        id: 'Folder yang Dikecualikan',
        zh: '排除的文件夹',
        es: 'Carpetas excluidas',
        pt: 'Pastas excluídas',
        ja: '除外フォルダ',
        ko: '제외된 폴더',
        hi: 'छोड़े गए फ़ोल्डर',
        ar: 'المجلدات المستبعدة',
        fr: 'Dossiers exclus',
        ru: 'Исключенные папки',
      );

  String get none => _t(
        en: 'None',
        id: 'Tidak ada',
        zh: '无',
        es: 'Ninguno',
        pt: 'Nenhum',
        ja: 'なし',
        ko: '없음',
        hi: 'कोई नहीं',
        ar: 'لا يوجد',
        fr: 'Aucun',
        ru: 'Нет',
      );

  String get allFilesAccess => _t(
        en: 'All Files Access (Android 11+)',
        id: 'Akses Semua File (Android 11+)',
        zh: '所有文件访问权限 (Android 11+)',
        es: 'Acceso a todos los archivos (Android 11+)',
        pt: 'Acesso a todos os arquivos (Android 11+)',
        ja: 'すべてのファイルへのアクセス (Android 11+)',
        ko: '모든 파일 액세스 (Android 11+)',
        hi: 'सभी फ़ाइलों तक पहुँच (Android 11+)',
        ar: 'الوصول إلى جميع الملفات (Android 11+)',
        fr: 'Accès à tous les fichiers (Android 11+)',
        ru: 'Доступ ко всем файлам (Android 11+)',
      );

  String get allFilesAccessSubtitle => _t(
        en: 'Enables complete trash and deletion across storage',
        id: 'Mengaktifkan fitur sampah dan penghapusan di seluruh memori',
        zh: '允许在整个存储中执行回收和删除',
        es: 'Permite papelera y eliminación en todo el almacenamiento',
        pt: 'Permite lixeira e exclusão em todo o armazenamento',
        ja: 'ストレージ全体のゴミ箱と削除を有効化',
        ko: '전체 저장소에서 휴지통 및 삭제 활성화',
        hi: 'पूरे स्टोरेज में ट्रैश और विलोपन सक्षम करें',
        ar: 'تمكين إدارة سلة المهملات والحذف عبر الذاكرة',
        fr: 'Active la corbeille et la suppression sur tout le stockage',
        ru: 'Включает корзину и удаление по всему накопителю',
      );

  String get updates => _t(
        en: 'Updates',
        id: 'Pembaruan',
        zh: '更新',
        es: 'Actualizaciones',
        pt: 'Atualizações',
        ja: '更新',
        ko: '업데이트',
        hi: 'अपडेट',
        ar: 'التحديثات',
        fr: 'Mises à jour',
        ru: 'Обновления',
      );

  String get autoCheckUpdate => _t(
        en: 'Auto-check for Updates',
        id: 'Cek Pembaruan Otomatis',
        zh: '自动检查更新',
        es: 'Buscar actualizaciones automáticamente',
        pt: 'Verificar atualizações automaticamente',
        ja: '自動更新確認',
        ko: '업데이트 자동 확인',
        hi: 'स्वचालित रूप से अपडेट जांचें',
        ar: 'التحقق التلقائي من التحديثات',
        fr: 'Vérification automatique des mises à jour',
        ru: 'Автопроверка обновлений',
      );

  String get checkUpdateNow => _t(
        en: 'Check for Updates',
        id: 'Cek Pembaruan Sekarang',
        zh: '检查更新',
        es: 'Buscar actualizaciones ahora',
        pt: 'Verificar atualizações agora',
        ja: '更新を確認',
        ko: '지금 업데이트 확인',
        hi: 'अपडेट जांचें',
        ar: 'التحقق من وجود تحديثات الآن',
        fr: 'Vérifier les mises à jour',
        ru: 'Проверить обновления',
      );

  String get about => _t(
        en: 'About',
        id: 'Tentang',
        zh: '关于',
        es: 'Acerca de',
        pt: 'Sobre',
        ja: 'アプリ情報',
        ko: '정보',
        hi: 'के बारे में',
        ar: 'حول التطبيق',
        fr: 'À propos',
        ru: 'О приложении',
      );

  String get resetAllSettings => _t(
        en: 'Reset All Settings',
        id: 'Reset Semua Pengaturan',
        zh: '重置所有设置',
        es: 'Restablecer todos los ajustes',
        pt: 'Redefinir todas as configurações',
        ja: 'すべての設定をリセット',
        ko: '모든 설정 초기화',
        hi: 'सभी सेटिंग्स रीसेट करें',
        ar: 'إعادة تعيين جميع الإعدادات',
        fr: 'Réinitialiser tous les paramètres',
        ru: 'Сбросить все настройки',
      );

  // ── Actions & Dialogs ──────────────────────────────────────────────────────
  String get cancel => _t(
        en: 'Cancel',
        id: 'Batal',
        zh: '取消',
        es: 'Cancelar',
        pt: 'Cancelar',
        ja: 'キャンセル',
        ko: '취소',
        hi: 'रद्द करें',
        ar: 'إلغاء',
        fr: 'Annuler',
        ru: 'Отмена',
      );

  String get save => _t(
        en: 'Save',
        id: 'Simpan',
        zh: '保存',
        es: 'Guardar',
        pt: 'Salvar',
        ja: '保存',
        ko: '저장',
        hi: 'सहेजें',
        ar: 'حفظ',
        fr: 'Enregistrer',
        ru: 'Сохранить',
      );

  String get add => _t(
        en: 'Add',
        id: 'Tambah',
        zh: '添加',
        es: 'Añadir',
        pt: 'Adicionar',
        ja: '追加',
        ko: '추가',
        hi: 'जोड़ें',
        ar: 'إضافة',
        fr: 'Ajouter',
        ru: 'Добавить',
      );

  String get delete => _t(
        en: 'Delete',
        id: 'Hapus',
        zh: '删除',
        es: 'Eliminar',
        pt: 'Excluir',
        ja: '削除',
        ko: '삭제',
        hi: 'हटाएं',
        ar: 'حذف',
        fr: 'Supprimer',
        ru: 'Удалить',
      );

  String get share => _t(
        en: 'Share',
        id: 'Bagikan',
        zh: '分享',
        es: 'Compartir',
        pt: 'Compartilhar',
        ja: '共有',
        ko: '공유',
        hi: 'साझा करें',
        ar: 'مشاركة',
        fr: 'Partager',
        ru: 'Поделиться',
      );

  String get pickFromManager => _t(
        en: 'Select from File Manager',
        id: 'Pilih lewat File Manager',
        zh: '从文件管理器中选择',
        es: 'Seleccionar desde el administrador de archivos',
        pt: 'Selecionar do gerenciador de arquivos',
        ja: 'ファイルマネージャーから選択',
        ko: '파일 관리자에서 선택',
        hi: 'फ़ाइल प्रबंधक से चुनें',
        ar: 'الاختيار من مدير الملفات',
        fr: 'Choisir depuis le gestionnaire de fichiers',
        ru: 'Выбрать из диспетчера файлов',
      );

  String get pickFromAlbums => _t(
        en: 'Detected Media Folders',
        id: 'Folder Media Terdeteksi',
        zh: '检测到的媒体文件夹',
        es: 'Carpetas de medios detectadas',
        pt: 'Pastas de mídia detectadas',
        ja: '検出されたメディアフォルダ',
        ko: '감지된 미디어 폴더',
        hi: 'पहचाने गए मीडिया फ़ोल्डर',
        ar: 'مجلدات الوسائط المكتشفة',
        fr: 'Dossiers multimédias détectés',
        ru: 'Обнаруженные папки мультимедиа',
      );

  String get manualPathEntry => _t(
        en: 'Enter path manually',
        id: 'Ketik path manual',
        zh: '手动输入路径',
        es: 'Introducir ruta manualmente',
        pt: 'Digitar caminho manualmente',
        ja: '手動でパスを入力',
        ko: '수동으로 경로 입력',
        hi: 'मैन्युअल रूप से पथ दर्ज करें',
        ar: 'أدخل المسار يدوياً',
        fr: 'Entrer le chemin manuellement',
        ru: 'Ввести путь вручную',
      );

  // ── Keep Screen On ────────────────────────────────────────────────────────
  String get keepScreenOn => _t(
        en: 'Keep screen on while viewing',
        id: 'Layar tetap menyala saat melihat',
        zh: '查看时保持屏幕常亮',
        es: 'Mantener pantalla encendida al ver',
        pt: 'Manter tela ligada ao visualizar',
        ja: '表示中に画面を常時点灯',
        ko: '보는 동안 화면 켜짐 유지',
        hi: 'देखते समय स्क्रीन चालू रखें',
        ar: 'إبقاء الشاشة قيد التشغيل أثناء العرض',
        fr: 'Garder l\'écran allumé pendant la lecture',
        ru: 'Не выключать экран при просмотре',
      );

  String get keepScreenOnSubtitle => _t(
        en: 'Prevent screen from turning off while viewing media',
        id: 'Cegah layar mati saat melihat foto dan video',
        zh: '查看照片和视频时防止屏幕变暗或关闭',
        es: 'Evita que la pantalla se apague al ver fotos y vídeos',
        pt: 'Evita que a tela desligue ao ver fotos e vídeos',
        ja: '写真や動画を表示中に画面が消灯するのを防ぎます',
        ko: '사진 및 동영상을 보는 동안 화면이 꺼지지 않도록 합니다',
        hi: 'फ़ोटो और वीडियो देखते समय स्क्रीन बंद होने से रोकें',
        ar: 'منع إيقاف تشغيل الشاشة أثناء عرض الصور ومقاطع الفيديو',
        fr: 'Empêche l\'écran de s\'éteindre lors de la visualisation',
        ru: 'Не гасить экран при просмотре фото и видео',
      );

  // ── Sort & Direction ───────────────────────────────────────────────────────
  String get sort => _t(
        en: 'Sort',
        id: 'Urutkan',
        zh: '排序',
        es: 'Ordenar',
        pt: 'Ordenar',
        ja: '並べ替え',
        ko: '정렬',
        hi: 'क्रमबद्ध करें',
        ar: 'ترتيب',
        fr: 'Trier',
        ru: 'Сортировка',
      );

  String get restoreDefaults => _t(
        en: 'Restore defaults',
        id: 'Pulihkan default',
        zh: '恢复默认设置',
        es: 'Restablecer valores predeterminados',
        pt: 'Restaurar padrões',
        ja: 'デフォルトに戻す',
        ko: '기본값 복원',
        hi: 'डिफ़ॉल्ट पुनर्स्थापित करें',
        ar: 'استعادة الإعدادات الافتراضية',
        fr: 'Restaurer les valeurs par défaut',
        ru: 'Сбросить по умолчанию',
      );

  String get sortByShootingTime => _t(
        en: 'By shooting time',
        id: 'Waktu pengambilan',
        zh: '拍摄时间',
        es: 'Por fecha de captura',
        pt: 'Por data da foto',
        ja: '撮影日時順',
        ko: '촬영 시간순',
        hi: 'शूटिंग के समय के अनुसार',
        ar: 'حسب وقت الالتقاط',
        fr: 'Par date de prise de vue',
        ru: 'По дате съёмки',
      );

  String get sortByTimeAdded => _t(
        en: 'By time added',
        id: 'Waktu ditambahkan',
        zh: '添加时间',
        es: 'Por fecha de adición',
        pt: 'Por data de adição',
        ja: '追加日時順',
        ko: '추가된 시간순',
        hi: 'जोड़े जाने के समय के अनुसार',
        ar: 'حسب وقت الإضافة',
        fr: 'Par date d\'ajout',
        ru: 'По дате добавления',
      );

  String get sortByName => _t(
        en: 'By name',
        id: 'Berdasarkan nama',
        zh: '按名称',
        es: 'Por nombre',
        pt: 'Por nome',
        ja: '名前順',
        ko: '이름순',
        hi: 'नाम के अनुसार',
        ar: 'حسب الاسم',
        fr: 'Par nom',
        ru: 'По имени',
      );

  String get sortBySize => _t(
        en: 'By size',
        id: 'Berdasarkan ukuran',
        zh: '按大小',
        es: 'Por tamaño',
        pt: 'Por tamanho',
        ja: 'サイズ順',
        ko: '크기순',
        hi: 'आकार के अनुसार',
        ar: 'حسب الحجم',
        fr: 'Par taille',
        ru: 'По размеру',
      );

  String get oldestToNewest => _t(
        en: 'Oldest to newest',
        id: 'Terlama ke terbaru',
        zh: '从旧到新',
        es: 'De más antiguo a más reciente',
        pt: 'Do mais antigo ao mais recente',
        ja: '古い順',
        ko: '오래된 순',
        hi: 'पुराने से नया',
        ar: 'من الأقدم إلى الأحدث',
        fr: 'Du plus ancien au plus récent',
        ru: 'Сначала старые',
      );

  String get newestToOldest => _t(
        en: 'Newest to oldest',
        id: 'Terbaru ke terlama',
        zh: '从新到旧',
        es: 'De más reciente a más antiguo',
        pt: 'Do mais recente ao mais antigo',
        ja: '新しい順',
        ko: '최신 순',
        hi: 'नए से पुराना',
        ar: 'من الأحدث إلى الأقدم',
        fr: 'Du plus récent au plus ancien',
        ru: 'Сначала новые',
      );

  String get aToZ => _t(
        en: 'A to Z',
        id: 'A ke Z',
        zh: 'A 到 Z',
        es: 'A a Z',
        pt: 'A a Z',
        ja: 'AからZ',
        ko: 'A에서 Z',
        hi: 'A से Z',
        ar: 'من أ إلى ي',
        fr: 'De A à Z',
        ru: 'От А до Я',
      );

  String get zToA => _t(
        en: 'Z to A',
        id: 'Z ke A',
        zh: 'Z 到 A',
        es: 'Z a A',
        pt: 'Z a A',
        ja: 'ZからA',
        ko: 'Z에서 A',
        hi: 'Z से A',
        ar: 'من ي إلى أ',
        fr: 'De Z à A',
        ru: 'От Я до А',
      );

  String get smallestToLargest => _t(
        en: 'Smallest to largest',
        id: 'Terkecil ke terbesar',
        zh: '从小到大',
        es: 'De menor a mayor',
        pt: 'Do menor para o maior',
        ja: '小さい順',
        ko: '작은 순',
        hi: 'छोटे से बड़ा',
        ar: 'من الأصغر إلى الأكبر',
        fr: 'Du plus petit au plus grand',
        ru: 'Сначала меньшие',
      );

  String get largestToSmallest => _t(
        en: 'Largest to smallest',
        id: 'Terbesar ke terkecil',
        zh: '从大到小',
        es: 'De mayor a menor',
        pt: 'Do maior para o menor',
        ja: '大きい順',
        ko: '큰 순',
        hi: 'बड़े से छोटा',
        ar: 'من الأكبر إلى الأصغر',
        fr: 'Du plus grand au plus petit',
        ru: 'Сначала большие',
      );

  // ── Viewer Actions & Media Controls ────────────────────────────────────────
  String get restore => _t(
        en: 'Restore',
        id: 'Pulihkan',
        zh: '恢复',
        es: 'Restaurar',
        pt: 'Restaurar',
        ja: '復元',
        ko: '복원',
        hi: 'पुनर्स्थापित करें',
        ar: 'استعادة',
        fr: 'Restaurer',
        ru: 'Восстановить',
      );

  String get details => _t(
        en: 'Details',
        id: 'Rincian',
        zh: '详细信息',
        es: 'Detalles',
        pt: 'Detalhes',
        ja: '詳細',
        ko: '상세 정보',
        hi: 'विवरण',
        ar: 'التفاصيل',
        fr: 'Détails',
        ru: 'Сведения',
      );

  String get favorite => _t(
        en: 'Favorite',
        id: 'Favorit',
        zh: '收藏',
        es: 'Favorito',
        pt: 'Favorito',
        ja: 'お気に入り',
        ko: '즐겨찾기',
        hi: 'पसंदीदा',
        ar: 'المفضلة',
        fr: 'Favori',
        ru: 'В избранное',
      );

  String get more => _t(
        en: 'More',
        id: 'Lainnya',
        zh: '更多',
        es: 'Más',
        pt: 'Mais',
        ja: 'その他',
        ko: '더보기',
        hi: 'अधिक',
        ar: 'المزيد',
        fr: 'Plus',
        ru: 'Ещё',
      );

  String get play => _t(
        en: 'Play',
        id: 'Putar',
        zh: '播放',
        es: 'Reproducir',
        pt: 'Reproduzir',
        ja: '再生',
        ko: '재생',
        hi: 'चलाएं',
        ar: 'تشغيل',
        fr: 'Lire',
        ru: 'Воспроизвести',
      );

  String get pause => _t(
        en: 'Pause',
        id: 'Jeda',
        zh: '暂停',
        es: 'Pausar',
        pt: 'Pausar',
        ja: '一時停止',
        ko: '일시정지',
        hi: 'रोकें',
        ar: 'إيقاف مؤقت',
        fr: 'Pause',
        ru: 'Пауза',
      );

  String get speed => _t(
        en: 'Speed',
        id: 'Kecepatan',
        zh: '速度',
        es: 'Velocidad',
        pt: 'Velocidade',
        ja: '速度',
        ko: '속도',
        hi: 'गति',
        ar: 'السرعة',
        fr: 'Vitesse',
        ru: 'Скорость',
      );

  String get normal => _t(
        en: 'Normal',
        id: 'Normal',
        zh: '正常',
        es: 'Normal',
        pt: 'Normal',
        ja: '標準',
        ko: '보통',
        hi: 'सामान्य',
        ar: 'عادي',
        fr: 'Normal',
        ru: 'Обычная',
      );

  String get loopOn => _t(
        en: 'Loop: On',
        id: 'Ulangi: Aktif',
        zh: '循环：开启',
        es: 'Bucle: Activado',
        pt: 'Repetir: Ativado',
        ja: 'リピート: オン',
        ko: '반복: 켜짐',
        hi: 'लूप: चालू',
        ar: 'التكرار: تشغيل',
        fr: 'Répéter : Activé',
        ru: 'Повтор: Вкл',
      );

  String get loopOff => _t(
        en: 'Loop: Off',
        id: 'Ulangi: Mati',
        zh: '循环：关闭',
        es: 'Bucle: Desactivado',
        pt: 'Repetir: Desativado',
        ja: 'リピート: オフ',
        ko: '반복: 꺼짐',
        hi: 'लूप: बंद',
        ar: 'التكرار: إيقاف',
        fr: 'Répéter : Désactivé',
        ru: 'Повтор: Выкл',
      );

  String get fullscreen => _t(
        en: 'Fullscreen',
        id: 'Layar Penuh',
        zh: '全屏',
        es: 'Pantalla completa',
        pt: 'Tela cheia',
        ja: '全画面表示',
        ko: '전체화면',
        hi: 'पूर्ण स्क्रीन',
        ar: 'ملء الشاشة',
        fr: 'Plein écran',
        ru: 'Полный экран',
      );

  String get exitFullscreen => _t(
        en: 'Exit Fullscreen',
        id: 'Keluar Layar Penuh',
        zh: '退出全屏',
        es: 'Salir de pantalla completa',
        pt: 'Sair da tela cheia',
        ja: '全画面を終了',
        ko: '전체화면 종료',
        hi: 'पूर्ण स्क्रीन से बाहर निकलें',
        ar: 'إنهاء ملء الشاشة',
        fr: 'Quitter le plein écran',
        ru: 'Выйти из полноэкранного режима',
      );

  String get loopEnabled => _t(
        en: 'Loop enabled',
        id: 'Ulangi diaktifkan',
        zh: '已开启循环',
        es: 'Bucle activado',
        pt: 'Repetição ativada',
        ja: 'リピートを有効にしました',
        ko: '반복 재생 켜짐',
        hi: 'लूप सक्षम',
        ar: 'تم تفعيل التكرار',
        fr: 'Répétition activée',
        ru: 'Повтор включен',
      );

  String get loopDisabled => _t(
        en: 'Loop disabled',
        id: 'Ulangi dinonaktifkan',
        zh: '已关闭循环',
        es: 'Bucle desactivado',
        pt: 'Repetição desativada',
        ja: 'リピートを無効にしました',
        ko: '반복 재생 꺼짐',
        hi: 'लूप अक्षम',
        ar: 'تم إيقاف التكرار',
        fr: 'Répétition désactivée',
        ru: 'Повтор выключен',
      );

  String get playbackSpeedTitle => _t(
        en: 'Playback Speed',
        id: 'Kecepatan Pemutaran',
        zh: '播放速度',
        es: 'Velocidad de reproducción',
        pt: 'Velocidade de reprodução',
        ja: '再生速度',
        ko: '재생 속도',
        hi: 'प्लेबैक गति',
        ar: 'سرعة التشغيل',
        fr: 'Vitesse de lecture',
        ru: 'Скорость воспроизведения',
      );

  // ── Rename & Wallpaper ────────────────────────────────────────────────────
  String get rename => _t(
        en: 'Rename',
        id: 'Ganti Nama',
        zh: '重命名',
        es: 'Renombrar',
        pt: 'Renomear',
        ja: '名前を変更',
        ko: '이름 변경',
        hi: 'नाम बदलें',
        ar: 'إعادة تسمية',
        fr: 'Renommer',
        ru: 'Переименовать',
      );

  String get setAsWallpaper => _t(
        en: 'Set as wallpaper',
        id: 'Jadikan wallpaper',
        zh: '设为壁纸',
        es: 'Establecer como fondo',
        pt: 'Definir como papel de parede',
        ja: '壁紙に設定',
        ko: '배경화면으로 설정',
        hi: 'वॉलपेपर के रूप में सेट करें',
        ar: 'تعيين كخلفية',
        fr: 'Définir comme fond d\'écran',
        ru: 'Установить как обои',
      );

  String get renameFile => _t(
        en: 'Rename File',
        id: 'Ganti Nama File',
        zh: '重命名文件',
        es: 'Renombrar archivo',
        pt: 'Renomear arquivo',
        ja: 'ファイル名を変更',
        ko: '파일 이름 변경',
        hi: 'फ़ाइल का नाम बदलें',
        ar: 'إعادة تسمية الملف',
        fr: 'Renommer le fichier',
        ru: 'Переименовать файл',
      );

  String get fileName => _t(
        en: 'File Name',
        id: 'Nama File',
        zh: '文件名',
        es: 'Nombre del archivo',
        pt: 'Nome do arquivo',
        ja: 'ファイル名',
        ko: '파일 이름',
        hi: 'फ़ाइल का नाम',
        ar: 'اسم الملف',
        fr: 'Nom du fichier',
        ru: 'Имя файла',
      );

  String get nameCannotBeEmpty => _t(
        en: 'Name cannot be empty',
        id: 'Nama tidak boleh kosong',
        zh: '名称不能为空',
        es: 'El nombre no puede estar vacío',
        pt: 'O nome não pode ficar vazio',
        ja: '名前を入力してください',
        ko: '이름은 비워둘 수 없습니다',
        hi: 'नाम खाली नहीं हो सकता',
        ar: 'لا يمكن أن يكون الاسم فارغاً',
        fr: 'Le nom ne peut pas être vide',
        ru: 'Имя не может быть пустым',
      );

  String get containsInvalidCharacters => _t(
        en: 'Contains invalid characters',
        id: 'Mengandung karakter yang tidak valid',
        zh: '包含无效字符',
        es: 'Contiene caracteres no válidos',
        pt: 'Contém caracteres inválidos',
        ja: '無効な文字が含まれています',
        ko: '유효하지 않은 문자가 포함되어 있습니다',
        hi: 'अमान्य वर्ण शामिल हैं',
        ar: 'يحتوي على أحرف غير صالحة',
        fr: 'Contient des caractères non valides',
        ru: 'Содержит недопустимые символы',
      );

  String get fileAlreadyExists => _t(
        en: 'A file with this name already exists',
        id: 'File dengan nama ini sudah ada',
        zh: '同名文件已存在',
        es: 'Ya existe un archivo con este nombre',
        pt: 'Já existe um arquivo com esse nome',
        ja: '同名のファイルが既に存在します',
        ko: '같은 이름의 파일이 이미 존재합니다',
        hi: 'इस नाम की फ़ाइल पहले से मौजूद है',
        ar: 'يوجد ملف بهذا الاسم بالفعل',
        fr: 'Un fichier avec ce nom existe déjà',
        ru: 'Файл с таким именем уже существует',
      );

  String renamedTo(String name) => switch (_lang) {
        'id' => 'Nama diubah menjadi "$name"',
        'zh' => '已重命名为 "$name"',
        'es' => 'Renombrado a "$name"',
        'pt' => 'Renomeado para "$name"',
        'ja' => '"$name" に名前を変更しました',
        'ko' => '"$name"(으)로 이름 변경됨',
        'hi' => '"$name" में बदला गया',
        'ar' => 'تمت إعادة التسمية إلى "$name"',
        'fr' => 'Renommé en "$name"',
        'ru' => 'Переименовано в "$name"',
        _ => 'Renamed to "$name"',
      };

  String failedToRename(String err) => switch (_lang) {
        'id' => 'Gagal mengubah nama: $err',
        'zh' => '重命名失败: $err',
        'es' => 'Error al renombrar: $err',
        'pt' => 'Falha ao renomear: $err',
        'ja' => '名前の変更に失敗しました: $err',
        'ko' => '이름 변경 실패: $err',
        'hi' => 'नाम बदलने में विफल: $err',
        'ar' => 'فشلت إعادة التسمية: $err',
        'fr' => 'Échec du renommage : $err',
        'ru' => 'Не удалось переименовать: $err',
        _ => 'Failed to rename: $err',
      };

  // ── Deletion & Trash Dialogs ───────────────────────────────────────────────
  String get deletePermanentlyTitle => _t(
        en: 'Delete Permanently?',
        id: 'Hapus Permanen?',
        zh: '永久删除？',
        es: '¿Eliminar permanentemente?',
        pt: 'Excluir permanentemente?',
        ja: '完全に削除しますか？',
        ko: '영구 삭제하시겠습니까?',
        hi: 'स्थायी रूप से हटाएं?',
        ar: 'حذف نهائياً؟',
        fr: 'Supprimer définitivement ?',
        ru: 'Удалить навсегда?',
      );

  String deletePermanentlyItemDesc(String name) => switch (_lang) {
        'id' => '"$name" akan dihapus secara permanen. Tindakan ini tidak dapat dibatalkan.',
        'zh' => '"$name" 将被永久删除。此操作无法撤消。',
        'es' => '"$name" se eliminará permanentemente. Esta acción no se puede deshacer.',
        'pt' => '"$name" será excluído permanentemente. Esta ação não pode ser desfeita.',
        'ja' => '「$name」は完全に削除されます。この操作は取り消せません。',
        'ko' => '"$name"이(가) 영구적으로 삭제됩니다. 이 작업은 취소할 수 없습니다.',
        'hi' => '"$name" स्थायी रूप से हटा दिया जाएगा। इसे पूर्ववत नहीं किया जा सकता।',
        'ar' => 'سيتم حذف "$name" نهائياً. لا يمكن التراجع عن هذا الإجراء.',
        'fr' => '"$name" sera définitivement supprimé. Cette action est irréversible.',
        'ru' => '"$name" будет удален безвозвратно. Это действие нельзя отменить.',
        _ => '"$name" will be permanently deleted. This action cannot be undone.',
      };

  String get moveToTrashTitle => _t(
        en: 'Move to Trash?',
        id: 'Pindahkan ke Sampah?',
        zh: '移至回收站？',
        es: '¿Mover a la papelera?',
        pt: 'Mover para a lixeira?',
        ja: 'ゴミ箱に移動しますか？',
        ko: '휴지통으로 이동하시겠습니까?',
        hi: 'रीसायकल बिन में ले जाएं?',
        ar: 'نقل إلى سلة المهملات؟',
        fr: 'Mettre à la corbeille ?',
        ru: 'Переместить в корзину?',
      );

  String moveToTrashItemDesc(String name) => switch (_lang) {
        'id' => '"$name" akan dipindahkan ke tempat sampah.',
        'zh' => '"$name" 将被移至回收站。',
        'es' => '"$name" se moverá a la papelera.',
        'pt' => '"$name" será movido para a lixeira.',
        'ja' => '「$name」はゴミ箱に移動されます。',
        'ko' => '"$name"이(가) 휴지통으로 이동됩니다.',
        'hi' => '"$name" रीसायकल बिन में ले जाया जाएगा।',
        'ar' => 'سيتم نقل "$name" إلى سلة المهملات.',
        'fr' => '"$name" sera déplacé vers la corbeille.',
        'ru' => '"$name" будет перемещен в корзину.',
        _ => '"$name" will be moved to trash.',
      };

  String get moveToTrash => _t(
        en: 'Move to Trash',
        id: 'Pindahkan ke Sampah',
        zh: '移至回收站',
        es: 'Mover a la papelera',
        pt: 'Mover para a lixeira',
        ja: 'ゴミ箱へ移動',
        ko: '휴지통으로 이동',
        hi: 'रीसायकल बिन में ले जाएं',
        ar: 'نقل إلى سلة المهملات',
        fr: 'Mettre à la corbeille',
        ru: 'В корзину',
      );

  String itemRestored(String name) => switch (_lang) {
        'id' => '"$name" telah dipulihkan',
        'zh' => '"$name" 已恢复',
        'es' => '"$name" restaurado',
        'pt' => '"$name" restaurado',
        'ja' => '「$name」を復元しました',
        'ko' => '"$name" 복원됨',
        'hi' => '"$name" पुनर्स्थापित किया गया',
        'ar' => 'تمت استعادة "$name"',
        'fr' => '"$name" restauré',
        'ru' => '"$name" восстановлен',
        _ => '"$name" restored',
      };

  String itemsRestoredCount(int count) => switch (_lang) {
        'id' => '$count item dipulihkan',
        'zh' => '已恢复 $count 个项目',
        'es' => '$count elemento(s) restaurado(s)',
        'pt' => '$count item(ns) restaurado(s)',
        'ja' => '$count 件を復元しました',
        'ko' => '$count개 항목 복원됨',
        'hi' => '$count आइटम पुनर्स्थापित किए गए',
        'ar' => 'تمت استعادة $count عنصر',
        'fr' => '$count élément(s) restauré(s)',
        'ru' => 'Восстановлено: $count',
        _ => '$count item${count == 1 ? '' : 's'} restored',
      };

  String get manageFilesPermissionRequired => _t(
        en: 'Manage All Files permission is required for this operation.',
        id: 'Izin Akses Semua File diperlukan untuk operasi ini.',
        zh: '此操作需要“所有文件访问权限”。',
        es: 'Se requiere el permiso de Administrar todos los archivos para esta acción.',
        pt: 'A permissão de Acesso a todos os arquivos é necessária para esta operação.',
        ja: 'この操作には「すべてのファイルへのアクセス」権限が必要です。',
        ko: '이 작업을 수행하려면 모든 파일 관리 권한이 필요합니다.',
        hi: 'इस कार्य के लिए सभी फ़ाइलों का प्रबंधन करने की अनुमति आवश्यक है।',
        ar: 'مطلوب إذن إدارة جميع الملفات لهذه العملية.',
        fr: 'L\'autorisation Accès à tous les fichiers est requise pour cette opération.',
        ru: 'Для этой операции требуется разрешение на управление всеми файлами.',
      );

  String failedToDelete(String err) => switch (_lang) {
        'id' => 'Gagal menghapus: $err',
        'zh' => '删除失败: $err',
        'es' => 'Error al eliminar: $err',
        'pt' => 'Falha ao excluir: $err',
        'ja' => '削除に失敗しました: $err',
        'ko' => '삭제 실패: $err',
        'hi' => 'हटाने में विफल: $err',
        'ar' => 'فشل الحذف: $err',
        'fr' => 'Échec de la suppression : $err',
        'ru' => 'Не удалось удалить: $err',
        _ => 'Failed to delete: $err',
      };

  // ── Media Info Sheet ───────────────────────────────────────────────────────
  String get name => _t(
        en: 'Name',
        id: 'Nama',
        zh: '名称',
        es: 'Nombre',
        pt: 'Nome',
        ja: '名前',
        ko: '이름',
        hi: 'नाम',
        ar: 'الاسم',
        fr: 'Nom',
        ru: 'Имя',
      );

  String get date => _t(
        en: 'Date',
        id: 'Tanggal',
        zh: '日期',
        es: 'Fecha',
        pt: 'Data',
        ja: '日付',
        ko: '날짜',
        hi: 'तारीख',
        ar: 'التاريخ',
        fr: 'Date',
        ru: 'Дата',
      );

  String get size => _t(
        en: 'Size',
        id: 'Ukuran',
        zh: '大小',
        es: 'Tamaño',
        pt: 'Tamanho',
        ja: 'サイズ',
        ko: '크기',
        hi: 'आकार',
        ar: 'الحجم',
        fr: 'Taille',
        ru: 'Размер',
      );

  String get resolution => _t(
        en: 'Resolution',
        id: 'Resolusi',
        zh: '分辨率',
        es: 'Resolución',
        pt: 'Resolução',
        ja: '解像度',
        ko: '해상도',
        hi: 'रिज़ॉल्यूशन',
        ar: 'الدقة',
        fr: 'Résolution',
        ru: 'Разрешение',
      );

  String get frameRate => _t(
        en: 'Frame Rate',
        id: 'Frame Rate',
        zh: '帧率',
        es: 'Frecuencia de cuadros',
        pt: 'Taxa de quadros',
        ja: 'フレームレート',
        ko: '프레임 속도',
        hi: 'फ़्रेम दर',
        ar: 'معدل الإطارات',
        fr: 'Fréquence d\'images',
        ru: 'Частота кадров',
      );

  String get codec => _t(
        en: 'Codec',
        id: 'Codec',
        zh: '编解码器',
        es: 'Códec',
        pt: 'Codec',
        ja: 'コーデック',
        ko: '코덱',
        hi: 'कोडेक',
        ar: 'برنامج الترميز',
        fr: 'Codec',
        ru: 'Кодек',
      );

  String get duration => _t(
        en: 'Duration',
        id: 'Durasi',
        zh: '时长',
        es: 'Duración',
        pt: 'Duração',
        ja: '再生時間',
        ko: '길이',
        hi: 'अवधि',
        ar: 'المدة',
        fr: 'Durée',
        ru: 'Длительность',
      );

  String get path => _t(
        en: 'Path',
        id: 'Lokasi Path',
        zh: '路径',
        es: 'Ruta',
        pt: 'Caminho',
        ja: 'パス',
        ko: '경로',
        hi: 'पथ',
        ar: 'المسار',
        fr: 'Chemin',
        ru: 'Путь',
      );

  String get copyPath => _t(
        en: 'Copy path',
        id: 'Salin path',
        zh: '复制路径',
        es: 'Copiar ruta',
        pt: 'Copiar caminho',
        ja: 'パスをコピー',
        ko: '경로 복사',
        hi: 'पथ कॉपी करें',
        ar: 'نسخ المسار',
        fr: 'Copier le chemin',
        ru: 'Копировать путь',
      );

  String get pathCopied => _t(
        en: 'Path copied to clipboard',
        id: 'Path disalin ke papan klip',
        zh: '路径已复制到剪贴板',
        es: 'Ruta copiada al portapapeles',
        pt: 'Caminho copiado para a área de transferência',
        ja: 'パスをクリップボードにコピーしました',
        ko: '경로가 클립보드에 복사되었습니다',
        hi: 'पथ क्लिपबोर्ड पर कॉपी किया गया',
        ar: 'تم نسخ المسار إلى الحافظة',
        fr: 'Chemin copié dans le presse-papiers',
        ru: 'Путь скопирован в буфер обмена',
      );

  // ── Gallery Screen & Selection ─────────────────────────────────────────────
  String get select => _t(
        en: 'Select',
        id: 'Pilih',
        zh: '选择',
        es: 'Seleccionar',
        pt: 'Selecionar',
        ja: '選択',
        ko: '선택',
        hi: 'चुनें',
        ar: 'تحديد',
        fr: 'Sélectionner',
        ru: 'Выбрать',
      );

  String get selectAll => _t(
        en: 'Select all',
        id: 'Pilih semua',
        zh: '全选',
        es: 'Seleccionar todo',
        pt: 'Selecionar tudo',
        ja: 'すべて選択',
        ko: '모두 선택',
        hi: 'सभी चुनें',
        ar: 'تحديد الكل',
        fr: 'Tout sélectionner',
        ru: 'Выбрать все',
      );

  String get deselectAll => _t(
        en: 'Deselect all',
        id: 'Batalkan semua pilihan',
        zh: '取消全选',
        es: 'Deseleccionar todo',
        pt: 'Desmarcar tudo',
        ja: '選択を全解除',
        ko: '모두 선택 해제',
        hi: 'सभी अचयनित करें',
        ar: 'إلغاء تحديد الكل',
        fr: 'Tout désélectionner',
        ru: 'Снять выделение',
      );

  String get deleteSelected => _t(
        en: 'Delete selected',
        id: 'Hapus yang dipilih',
        zh: '删除所选',
        es: 'Eliminar seleccionados',
        pt: 'Excluir selecionados',
        ja: '選択項目を削除',
        ko: '선택 항목 삭제',
        hi: 'चयनित हटाएं',
        ar: 'حذف المحدد',
        fr: 'Supprimer la sélection',
        ru: 'Удалить выбранное',
      );

  String get deleteSelectedAlbums => _t(
        en: 'Delete selected albums',
        id: 'Hapus album yang dipilih',
        zh: '删除所选相册',
        es: 'Eliminar álbumes seleccionados',
        pt: 'Excluir álbuns selecionados',
        ja: '選択したアルバムを削除',
        ko: '선택한 앨범 삭제',
        hi: 'चयनित एल्बम हटाएं',
        ar: 'حذف الألبومات المحددة',
        fr: 'Supprimer les albums sélectionnés',
        ru: 'Удалить выбранные альбомы',
      );

  String get searchTooltip => _t(
        en: 'Search',
        id: 'Cari',
        zh: '搜索',
        es: 'Buscar',
        pt: 'Pesquisar',
        ja: '検索',
        ko: '검색',
        hi: 'खोजें',
        ar: 'بحث',
        fr: 'Rechercher',
        ru: 'Поиск',
      );

  String get moreOptions => _t(
        en: 'More options',
        id: 'Opsi lainnya',
        zh: '更多选项',
        es: 'Más opciones',
        pt: 'Mais opções',
        ja: 'その他のオプション',
        ko: '더 많은 옵션',
        hi: 'अधिक विकल्प',
        ar: 'خيارات إضافية',
        fr: 'Plus d\'options',
        ru: 'Другие параметры',
      );

  String get noPhotosFound => _t(
        en: 'No photos found',
        id: 'Tidak ada foto',
        zh: '未找到照片',
        es: 'No se encontraron fotos',
        pt: 'Nenhuma foto encontrada',
        ja: '写真が見つかりません',
        ko: '사진이 없습니다',
        hi: 'कोई फ़ोटो नहीं मिली',
        ar: 'لم يتم العثور على صور',
        fr: 'Aucune photo trouvée',
        ru: 'Фотографии не найдены',
      );

  String get noVideosFound => _t(
        en: 'No videos found',
        id: 'Tidak ada video',
        zh: '未找到视频',
        es: 'No se encontraron vídeos',
        pt: 'Nenhum vídeo encontrado',
        ja: '動画が見つかりません',
        ko: '동영상이 없습니다',
        hi: 'कोई वीडियो नहीं मिला',
        ar: 'لم يتم العثور على مقاطع فيديو',
        fr: 'Aucune vidéo trouvée',
        ru: 'Видео не найдены',
      );

  String get noAlbumsFound => _t(
        en: 'No albums found',
        id: 'Tidak ada album',
        zh: '未找到相册',
        es: 'No se encontraron álbumes',
        pt: 'Nenhum álbum encontrado',
        ja: 'アルバムが見つかりません',
        ko: '앨범이 없습니다',
        hi: 'कोई एल्बम नहीं मिला',
        ar: 'لم يتم العثور على ألبومات',
        fr: 'Aucun album trouvé',
        ru: 'Альбомы не найдены',
      );

  String noMediaMatching(String query) => switch (_lang) {
        'id' => 'Tidak ada media yang cocok dengan "$query"',
        'zh' => '未找到与 "$query" 匹配的媒体',
        'es' => 'No hay medios que coincidan con "$query"',
        'pt' => 'Nenhuma mídia correspondente a "$query"',
        'ja' => '「$query」に一致するメディアはありません',
        'ko' => '"$query"와(과) 일치하는 미디어가 없습니다',
        'hi' => '"$query" से मेल खाने वाला कोई मीडिया नहीं है',
        'ar' => 'لا توجد وسائط تطابق "$query"',
        'fr' => 'Aucun média correspondant à "$query"',
        'ru' => 'Медиа по запросу "$query" не найдены',
        _ => 'No media matching "$query"',
      };

  String noAlbumsMatching(String query) => switch (_lang) {
        'id' => 'Tidak ada album yang cocok dengan "$query"',
        'zh' => '未找到与 "$query" 匹配的相册',
        'es' => 'No hay álbumes que coincidan con "$query"',
        'pt' => 'Nenhum álbum correspondente a "$query"',
        'ja' => '「$query」に一致するアルバムはありません',
        'ko' => '"$query"와(과) 일치하는 앨범이 없습니다',
        'hi' => '"$query" से मेल खाने वाला कोई एल्बम नहीं है',
        'ar' => 'لا توجد ألبومات تطابق "$query"',
        'fr' => 'Aucun album correspondant à "$query"',
        'ru' => 'Альбомы по запросу "$query" не найдены',
        _ => 'No albums matching "$query"',
      };

  String itemsCount(int count) => switch (_lang) {
        'id' => '$count item',
        'zh' => '$count 项',
        'es' => '$count elemento${count == 1 ? '' : 's'}',
        'pt' => '$count item${count == 1 ? '' : 's'}',
        'ja' => '$count 項目',
        'ko' => '$count개 항목',
        'hi' => '$count आइटम',
        'ar' => '$count عنصر',
        'fr' => '$count élément${count == 1 ? '' : 's'}',
        'ru' => '$count элемент(ов)',
        _ => '$count item${count == 1 ? '' : 's'}',
      };

  String albumsCount(int count) => switch (_lang) {
        'id' => '$count album',
        'zh' => '$count 个相册',
        'es' => '$count álbum${count == 1 ? '' : 'es'}',
        'pt' => '$count álbum${count == 1 ? '' : 'ns'}',
        'ja' => '$count アルバム',
        'ko' => '$count개 앨범',
        'hi' => '$count एल्बम',
        'ar' => '$count ألبوم',
        'fr' => '$count album${count == 1 ? '' : 's'}',
        'ru' => '$count альбом(ов)',
        _ => '$count album${count == 1 ? '' : 's'}',
      };

  // ── Trash Screen ───────────────────────────────────────────────────────────
  String get recentlyDeleted => _t(
        en: 'Recently deleted',
        id: 'Baru saja dihapus',
        zh: '最近删除',
        es: 'Eliminado recientemente',
        pt: 'Excluídos recentemente',
        ja: '最近削除した項目',
        ko: '최근 삭제된 항목',
        hi: 'हाल ही में हटाया गया',
        ar: 'المحذوفات حديثاً',
        fr: 'Récemment supprimés',
        ru: 'Недавно удаленные',
      );

  String get selectItems => _t(
        en: 'Select items',
        id: 'Pilih item',
        zh: '选择项目',
        es: 'Seleccionar elementos',
        pt: 'Selecionar itens',
        ja: '項目を選択',
        ko: '항목 선택',
        hi: 'आइटम चुनें',
        ar: 'تحديد العناصر',
        fr: 'Sélectionner des éléments',
        ru: 'Выберите элементы',
      );

  String get trashRetentionNote => _t(
        en: 'Deleted content is kept for 30 days before permanent deletion.',
        id: 'Konten yang dihapus disimpan selama 30 hari sebelum dihapus permanen.',
        zh: '删除的内容将在永久删除前保留30天。',
        es: 'El contenido eliminado se conserva durante 30 días antes de su eliminación permanente.',
        pt: 'O conteúdo excluído é mantido por 30 dias antes da exclusão permanente.',
        ja: '削除されたコンテンツは30日間保持された後に完全削除されます。',
        ko: '삭제된 콘텐츠는 30일 동안 보관된 후 영구 삭제됩니다.',
        hi: 'हटाया गया डेटा स्थायी रूप से हटाए जाने से पहले 30 दिनों तक रखा जाता है।',
        ar: 'يتم الاحتفاظ بالمحتوى المحذوف لمدة 30 يوماً قبل الحذف النهائي.',
        fr: 'Le contenu supprimé est conservé pendant 30 jours avant suppression définitive.',
        ru: 'Удаленные файлы хранятся 30 дней перед окончательным удалением.',
      );

  String get noRecentlyDeleted => _t(
        en: 'No recently deleted content',
        id: 'Tidak ada konten yang baru saja dihapus',
        zh: '没有最近删除的内容',
        es: 'No hay contenido eliminado recientemente',
        pt: 'Nenhum conteúdo excluído recentemente',
        ja: '最近削除されたコンテンツはありません',
        ko: '최근 삭제된 콘텐츠가 없습니다',
        hi: 'हाल ही में हटाई गई कोई सामग्री नहीं है',
        ar: 'لا يوجد محتوى محذوف مؤخراً',
        fr: 'Aucun contenu récemment supprimé',
        ru: 'В корзине пусто',
      );

  String get permanentlyDeleteAllTitle => _t(
        en: 'Permanently delete all items?',
        id: 'Hapus permanen semua item?',
        zh: '永久删除所有项目？',
        es: '¿Eliminar permanentemente todos los elementos?',
        pt: 'Excluir permanentemente todos os itens?',
        ja: 'すべての項目を完全に削除しますか？',
        ko: '모든 항목을 영구 삭제하시겠습니까?',
        hi: 'क्या सभी आइटम स्थायी रूप से हटाएं?',
        ar: 'حذف جميع العناصر نهائياً؟',
        fr: 'Supprimer définitivement tous les éléments ?',
        ru: 'Удалить навсегда все элементы?',
      );

  String permanentlyDeleteCountTitle(int count) => switch (_lang) {
        'id' => 'Hapus permanen $count item?',
        'zh' => '永久删除 $count 个项目？',
        'es' => '¿Eliminar permanentemente $count elemento${count == 1 ? '' : 's'}?',
        'pt' => 'Excluir permanentemente $count item(ns)?',
        'ja' => '$count 件を完全に削除しますか？',
        'ko' => '$count개 항목을 영구 삭제하시겠습니까?',
        'hi' => 'क्या $count आइटम स्थायी रूप से हटाएं?',
        'ar' => 'حذف $count عنصر نهائياً؟',
        'fr' => 'Supprimer définitivement $count élément${count == 1 ? '' : 's'} ?',
        'ru' => 'Удалить навсегда: $count?',
        _ => 'Permanently delete $count item${count == 1 ? '' : 's'}?',
      };

  String moveToTrashConfirm(String name) => switch (_lang) {
        'id' => 'Pindahkan "$name" ke tempat sampah?',
        'zh' => '将“$name”移至回收站？',
        'es' => '¿Mover "$name" a la papelera?',
        'pt' => 'Mover "$name" para a lixeira?',
        'ja' => '「$name」をゴミ箱に移動しますか？',
        'ko' => '"$name"을(를) 휴지통으로 이동하시겠습니까?',
        'hi' => 'क्या "$name" को रीसायकल बिन में ले जाएं?',
        'ar' => 'نقل "$name" إلى سلة المهملات؟',
        'fr' => 'Mettre « $name » à la corbeille ?',
        'ru' => 'Переместить "$name" в корзину?',
        _ => 'Move "$name" to trash?',
      };

  String deletePermanentlyConfirm(String name) => switch (_lang) {
        'id' => 'Hapus permanen "$name"?',
        'zh' => '永久删除“$name”？',
        'es' => '¿Eliminar permanentemente "$name"?',
        'pt' => 'Excluir permanentemente "$name"?',
        'ja' => '「$name」を完全に削除しますか？',
        'ko' => '"$name"을(를) 영구 삭제하시겠습니까?',
        'hi' => 'क्या "$name" को स्थायी रूप से हटाएं?',
        'ar' => 'حذف "$name" نهائياً؟',
        'fr' => 'Supprimer définitivement « $name » ?',
        'ru' => 'Удалить навсегда "$name"?',
        _ => 'Permanently delete "$name"?',
      };

  String daysLeft(int count) => switch (_lang) {
        'id' => 'Sisa $count hari',
        'zh' => '还剩 $count 天',
        'es' => 'Quedan $count días',
        'pt' => 'Restam $count dias',
        'ja' => '残り $count 日',
        'ko' => '$count일 남음',
        'hi' => '$count दिन शेष',
        'ar' => 'متبقي $count يوم',
        'fr' => '$count jours restants',
        'ru' => 'Осталось $count дн.',
        _ => '$count days left',
      };

  // ── Settings Subtitles & Dialogs ───────────────────────────────────────────
  String columnsCount(int count) => switch (_lang) {
        'id' => '$count kolom',
        'zh' => '$count 列',
        'es' => '$count columnas',
        'pt' => '$count colunas',
        'ja' => '$count 列',
        'ko' => '$count개 열',
        'hi' => '$count कॉलम',
        'ar' => '$count أعمدة',
        'fr' => '$count colonnes',
        'ru' => '$count столбца(ов)',
        _ => '$count columns',
      };

  String diskSize(String sizeStr) => switch (_lang) {
        'id' => 'Ukuran disk: $sizeStr',
        'zh' => '占用空间: $sizeStr',
        'es' => 'Tamaño en disco: $sizeStr',
        'pt' => 'Espaço em disco: $sizeStr',
        'ja' => 'ディスク容量: $sizeStr',
        'ko' => '디스크 용량: $sizeStr',
        'hi' => 'डिस्क आकार: $sizeStr',
        'ar' => 'حجم القرص: $sizeStr',
        'fr' => 'Taille sur disque : $sizeStr',
        'ru' => 'Размер на диске: $sizeStr',
        _ => 'Disk size: $sizeStr',
      };

  String get checkUpdateOnLaunchSubtitle => _t(
        en: 'Check GitHub Releases on launch',
        id: 'Cek rilis GitHub saat aplikasi dibuka',
        zh: '启动时检查 GitHub 发布版',
        es: 'Buscar versiones de GitHub al iniciar',
        pt: 'Verificar lançamentos do GitHub ao abrir',
        ja: '起動時にGitHubリリースを確認',
        ko: '앱 실행 시 GitHub 릴리스 확인',
        hi: 'लॉन्च पर GitHub रिलीज़ जांचें',
        ar: 'التحقق من إصدارات GitHub عند التشغيل',
        fr: 'Vérifier les versions GitHub au lancement',
        ru: 'Проверять релизы GitHub при запуске',
      );

  String get checkGitHubReleasesSubtitle => _t(
        en: 'Check GitHub for newer APK releases',
        id: 'Cek GitHub untuk rilis APK terbaru',
        zh: '在 GitHub 上检查较新的 APK 发布版',
        es: 'Buscar versiones de APK más recientes en GitHub',
        pt: 'Verificar no GitHub por APKs mais recentes',
        ja: '新しいAPKリリースをGitHubで確認',
        ko: '최신 APK 릴리스가 있는지 GitHub에서 확인',
        hi: 'नए APK रिलीज़ के लिए GitHub जांचें',
        ar: 'التحقق من GitHub بحثاً عن أحدث إصدارات APK',
        fr: 'Rechercher de nouveaux APK sur GitHub',
        ru: 'Проверить GitHub на наличие новых версий APK',
      );

  String get allFilesGranted => _t(
        en: 'All Files Access granted',
        id: 'Akses Semua File telah diizinkan',
        zh: '已授予“所有文件访问权限”',
        es: 'Acceso a todos los archivos concedido',
        pt: 'Acesso a todos os arquivos concedido',
        ja: 'すべてのファイルへのアクセスが許可されました',
        ko: '모든 파일 액세스 허용됨',
        hi: 'सभी फ़ाइलों तक पहुँच की अनुमति दी गई',
        ar: 'تم منح إذن الوصول إلى جميع الملفات',
        fr: 'Accès à tous les fichiers accordé',
        ru: 'Доступ ко всем файлам предоставлен',
      );

  String get allFilesNotGranted => _t(
        en: 'Manage All Files permission is not granted',
        id: 'Izin Akses Semua File belum diizinkan',
        zh: '未授予“所有文件访问权限”',
        es: 'No se otorgó el permiso de Administrar todos los archivos',
        pt: 'A permissão de Acesso a todos os arquivos não foi concedida',
        ja: 'すべてのファイルへのアクセス権限が許可されていません',
        ko: '모든 파일 관리 권한이 부여되지 않았습니다',
        hi: 'सभी फ़ाइलों के प्रबंधन की अनुमति नहीं दी गई',
        ar: 'لم يتم منح إذن إدارة جميع الملفات',
        fr: 'L\'autorisation Accès à tous les fichiers n\'est pas accordée',
        ru: 'Разрешение на доступ ко всем файлам не предоставлено',
      );

  String get supportedLanguagesCount => _t(
        en: '11 languages supported',
        id: '11 bahasa didukung',
        zh: '支持 11 种语言',
        es: '11 idiomas compatibles',
        pt: '11 idiomas suportados',
        ja: '11言語に対応',
        ko: '11개 언어 지원',
        hi: '11 भाषाएं समर्थित हैं',
        ar: '11 لغة مدعومة',
        fr: '11 langues prises en charge',
        ru: 'Поддерживается 11 языков',
      );

  String get selectTheme => _t(
        en: 'Select Theme',
        id: 'Pilih Tema',
        zh: '选择主题',
        es: 'Seleccionar tema',
        pt: 'Selecionar tema',
        ja: 'テーマを選択',
        ko: '테마 선택',
        hi: 'थीम चुनें',
        ar: 'اختر السمة',
        fr: 'Sélectionner le thème',
        ru: 'Выберите тему',
      );

  String get chooseVisualMode => _t(
        en: 'Choose visual mode and contrast',
        id: 'Pilih mode visual dan kontras',
        zh: '选择视觉模式和对比度',
        es: 'Elige modo visual y contraste',
        pt: 'Escolha o modo visual e o contraste',
        ja: '表示モードとコントラストを選択',
        ko: '화면 모드 및 대비 선택',
        hi: 'दृश्य मोड और कंट्रास्ट चुनें',
        ar: 'اختر وضع العرض والتباين',
        fr: 'Choisir le mode visuel et le contraste',
        ru: 'Выберите визуальный режим и контраст',
      );

  String themeModeLabel(AppThemeMode mode) => switch (mode) {
        AppThemeMode.system => _t(
            en: 'System',
            id: 'Sistem',
            zh: '系统跟随',
            es: 'Sistema',
            pt: 'Sistema',
            ja: 'システム',
            ko: '시스템',
            hi: 'सिस्टम',
            ar: 'النظام',
            fr: 'Système',
            ru: 'Системная',
          ),
        AppThemeMode.light => _t(
            en: 'Light',
            id: 'Terang',
            zh: '浅色模式',
            es: 'Claro',
            pt: 'Claro',
            ja: 'ライト',
            ko: '라이트',
            hi: 'लाइट',
            ar: 'فاتح',
            fr: 'Clair',
            ru: 'Светлая',
          ),
        AppThemeMode.dark => _t(
            en: 'Dark',
            id: 'Gelap',
            zh: '深色模式',
            es: 'Oscuro',
            pt: 'Escuro',
            ja: 'ダーク',
            ko: '다크',
            hi: 'डार्क',
            ar: 'داكن',
            fr: 'Sombre',
            ru: 'Темная',
          ),
        AppThemeMode.amoled => 'AMOLED',
        AppThemeMode.amoledSakura => switch (_lang) {
            'zh' => 'AMOLED 樱花粉 🌸',
            'ja' => 'AMOLED 桜 🌸',
            'ko' => 'AMOLED 사쿠라 🌸',
            'hi' => 'AMOLED सकुरा 🌸',
            'ar' => 'AMOLED ساكورا 🌸',
            'ru' => 'AMOLED Сакура 🌸',
            _ => 'AMOLED Sakura 🌸',
          },
      };

  String get themeSystemDesc => _t(
        en: 'Follows device system settings',
        id: 'Mengikuti pengaturan sistem perangkat',
        zh: '跟随设备系统设置',
        es: 'Sigue la configuración del sistema del dispositivo',
        pt: 'Segue as configurações do sistema do dispositivo',
        ja: '端末のシステム設定に従う',
        ko: '기기 시스템 설정을 따름',
        hi: 'डिवाइस सिस्टम सेटिंग्स का पालन करता है',
        ar: 'يتبع إعدادات نظام الجهاز',
        fr: 'Suit les paramètres système de l\'appareil',
        ru: 'Следует системным настройкам устройства',
      );

  String get themeLightDesc => _t(
        en: 'Clean & bright daytime palette',
        id: 'Palet siang hari yang bersih & cerah',
        zh: '清爽明亮的日间配色',
        es: 'Paleta diurna limpia y brillante',
        pt: 'Paleta diurna limpa e brilhante',
        ja: 'クリーンで明るい昼間向けテーマ',
        ko: '깔끔하고 밝은 주간 테マ',
        hi: 'साफ़ और चमकदार दिन का रंग पैलेट',
        ar: 'لوحة نهارية نظيفة ومشرقة',
        fr: 'Palette diurne épurée et lumineuse',
        ru: 'Чистая и светлая дневная палитра',
      );

  String get themeDarkDesc => _t(
        en: 'Sleek charcoal dark mode',
        id: 'Mode gelap arang yang elegan',
        zh: '优雅的深炭灰暗色模式',
        es: 'Modo oscuro carbón elegante',
        pt: 'Modo escuro carvão elegante',
        ja: '洗練されたチャコールダークモード',
        ko: '세련된 차콜 다크 모드',
        hi: 'चिकना चारकोल डार्क मोड',
        ar: 'وضع داكن أنيق بلون الفحم',
        fr: 'Mode sombre anthracite élégant',
        ru: 'Элегантный угольный темный режим',
      );

  String get themeAmoledDesc => _t(
        en: 'Pure pitch black for OLED displays',
        id: 'Hitam pekat murni untuk layar OLED',
        zh: '专为 OLED 屏幕打造的纯黑',
        es: 'Negro puro para pantallas OLED',
        pt: 'Preto puro para telas OLED',
        ja: 'OLEDディスプレイ向け完全な漆黒',
        ko: 'OLED 디스플레이를 위한 순수 칠흑색',
        hi: 'OLED डिस्प्ले के लिए शुद्ध गहरा काला',
        ar: 'أسود نقي لشاشات OLED',
        fr: 'Noir absolu pour écrans OLED',
        ru: 'Глубокий черный для OLED-экранов',
      );

  String get themeSakuraDesc => _t(
        en: 'Pure black with cherry sakura pink 🌸',
        id: 'Hitam pekat dengan merah muda bunga sakura 🌸',
        zh: '纯黑搭配樱花粉 🌸',
        es: 'Negro puro con rosa flor de cerezo 🌸',
        pt: 'Preto puro com rosa flor de cerejeira 🌸',
        ja: '漆黒に桜色のアクセント 🌸',
        ko: '순수 블랙과 벚꽃 핑크 🌸',
        hi: 'चेरी सकुरा गुलाबी के साथ शुद्ध काला 🌸',
        ar: 'أسود نقي مع وردي زهر الكرز 🌸',
        fr: 'Noir absolu avec rose fleur de cerisier 🌸',
        ru: 'Глубокий черный с акцентом сакуры 🌸',
      );

  String get selectGridColumns => _t(
        en: 'Select Grid Columns',
        id: 'Pilih Kolom Grid',
        zh: '选择网格列数',
        es: 'Seleccionar columnas de cuadrícula',
        pt: 'Selecionar colunas da grade',
        ja: 'グリッド列を選択',
        ko: '그리드 열 선택',
        hi: 'ग्रिड कॉलम चुनें',
        ar: 'اختر أعمدة الشبكة',
        fr: 'Sélectionner les colonnes de la grille',
        ru: 'Выберите количество столбцов',
      );

  String get selectAlbumsGridColumns => _t(
        en: 'Select Albums Grid Columns',
        id: 'Pilih Kolom Grid Album',
        zh: '选择相册网格列数',
        es: 'Seleccionar columnas de álbumes',
        pt: 'Selecionar colunas dos álbuns',
        ja: 'アルバム列を選択',
        ko: '앨범 열 선택',
        hi: 'एल्बम ग्रिड कॉलम चुनें',
        ar: 'اختر أعمدة شبكة الألبومات',
        fr: 'Sélectionner les colonnes des albums',
        ru: 'Выберите столбцы альбомов',
      );

  String get chooseThumbnailDensity => _t(
        en: 'Choose media thumbnail density',
        id: 'Pilih kerapatan thumbnail media',
        zh: '选择媒体缩略图密度',
        es: 'Elige la densidad de miniaturas',
        pt: 'Escolha a densidade das miniaturas',
        ja: 'メディアサムネイルの密度を選択',
        ko: '미디어 썸네일 밀도 선택',
        hi: 'मीडिया थंबनेल घनत्व चुनें',
        ar: 'اختر كثافة الصور المصغرة',
        fr: 'Choisir la densité des miniatures',
        ru: 'Выберите плотность миниатюр',
      );

  String get chooseAlbumDensity => _t(
        en: 'Choose album cards density',
        id: 'Pilih kerapatan kartu album',
        zh: '选择相册卡片密度',
        es: 'Elige la densidad de tarjetas de álbumes',
        pt: 'Escolha a densidade dos cards de álbuns',
        ja: 'アルバムカードの密度を選択',
        ko: '앨범 카드 밀도 선택',
        hi: 'एल्बम कार्ड घनत्व चुनें',
        ar: 'اختر كثافة بطاقات الألبوم',
        fr: 'Choisir la densité des cartes d\'albums',
        ru: 'Выберите плотность карточек альбомов',
      );

  String get largeComfortableView => _t(
        en: 'Large comfortable view',
        id: 'Tampilan besar dan nyaman',
        zh: '大尺寸舒适视图',
        es: 'Vista grande y cómoda',
        pt: 'Visualização ampla e confortável',
        ja: '大きく見やすい表示',
        ko: '크고 편안한 화면',
        hi: 'बड़ा और आरामदायक दृश्य',
        ar: 'عرض كبير ومريح',
        fr: 'Grande vue confortable',
        ru: 'Крупный комфортный вид',
      );

  String get standardBalanced => _t(
        en: 'Standard balanced (Default)',
        id: 'Standar seimbang (Default)',
        zh: '标准适中（默认）',
        es: 'Estándar equilibrado (Predeterminado)',
        pt: 'Padrão equilibrado (Padrão)',
        ja: '標準バランス（デフォルト）',
        ko: '표준 균형（기본값）',
        hi: 'मानक संतुलित (डिफ़ॉल्ट)',
        ar: 'قياسي متوازن (افتراضي)',
        fr: 'Standard équilibré (Par défaut)',
        ru: 'Стандартный сбалансированный (По умолчанию)',
      );

  String get compactDetailedView => _t(
        en: 'Compact detailed view',
        id: 'Tampilan ringkas mendetail',
        zh: '紧凑详细视图',
        es: 'Vista compacta y detallada',
        pt: 'Visualização compacta e detalhada',
        ja: 'コンパクトな一覧表示',
        ko: '간결하고 상세한 화면',
        hi: 'कॉम्पैक्ट विस्तृत दृश्य',
        ar: 'عرض مضغوط ومفصل',
        fr: 'Vue compacte détaillée',
        ru: 'Компактный детальный вид',
      );

  String get denseHighCapacity => _t(
        en: 'Dense high-capacity overview',
        id: 'Ikhtisar padat berkapasitas tinggi',
        zh: '高密度大容量概览',
        es: 'Vista previa densa de alta capacidad',
        pt: 'Visão geral densa de alta capacidade',
        ja: '高密度な大容量プレビュー',
        ko: '많은 항목을 볼 수 있는 고밀도 화면',
        hi: 'सघन उच्च-क्षमता अवलोकन',
        ar: 'نظرة عامة عالية الكثافة',
        fr: 'Aperçu dense haute capacité',
        ru: 'Плотный обзор высокой емкости',
      );

  // ── Developer Card ─────────────────────────────────────────────────────────
  String get aboutPhantek => _t(
        en: 'About Phantek',
        id: 'Tentang Phantek',
        zh: '关于 Phantek',
        es: 'Acerca de Phantek',
        pt: 'Sobre o Phantek',
        ja: 'Phantek について',
        ko: 'Phantek 정보',
        hi: 'Phantek के बारे में',
        ar: 'حول Phantek',
        fr: 'À propos de Phantek',
        ru: 'О Phantek',
      );

  String get offlineGalleryDesc => _t(
        en: 'Offline Gallery & Media Player',
        id: 'Galeri & Pemutar Media Offline',
        zh: '离线相册与媒体播放器',
        es: 'Galería y reproductor multimedia sin conexión',
        pt: 'Galeria e reprodutor de mídia offline',
        ja: 'オフラインギャラリー＆メディアプレーヤー',
        ko: '오프라인 갤러리 및 미디어 플레이어',
        hi: 'ऑफ़लाइन गैलरी और मीडिया प्लेयर',
        ar: 'معرض ومشغل وسائط بدون إنترنت',
        fr: 'Galerie et lecteur multimédia hors ligne',
        ru: 'Офлайн-галерея и медиаплеер',
      );

  String get appVersion => _t(
        en: 'App Version',
        id: 'Versi Aplikasi',
        zh: '应用版本',
        es: 'Versión de la aplicación',
        pt: 'Versão do aplicativo',
        ja: 'アプリのバージョン',
        ko: '앱 버전',
        hi: 'ऐप संस्करण',
        ar: 'إصدار التطبيق',
        fr: 'Version de l\'application',
        ru: 'Версия приложения',
      );

  String get buildNumberLabel => _t(
        en: 'Build',
        id: 'Build',
        zh: '构建版本',
        es: 'Compilación',
        pt: 'Build',
        ja: 'ビルド',
        ko: '빌드',
        hi: 'बिल्ड',
        ar: 'البنية',
        fr: 'Build',
        ru: 'Сборка',
      );

  String get architecture => _t(
        en: 'Architecture',
        id: 'Arsitektur',
        zh: '架构',
        es: 'Arquitectura',
        pt: 'Arquitetura',
        ja: 'アーキテクチャ',
        ko: '아키텍처',
        hi: 'आर्किटेक्चर',
        ar: 'المعمارية',
        fr: 'Architecture',
        ru: 'Архитектура',
      );

  String get license => _t(
        en: 'License',
        id: 'Lisensi',
        zh: '许可证',
        es: 'Licencia',
        pt: 'Licença',
        ja: 'ライセンス',
        ko: '라이선스',
        hi: 'लाइसेंस',
        ar: 'الترخيص',
        fr: 'Licence',
        ru: 'Лицензия',
      );

  String get developerLabel => _t(
        en: 'Developer: zerabyte88',
        id: 'Pengembang: zerabyte88',
        zh: '开发者：zerabyte88',
        es: 'Desarrollador: zerabyte88',
        pt: 'Desenvolvedor: zerabyte88',
        ja: '開発者: zerabyte88',
        ko: '개발者: zerabyte88',
        hi: 'डेवलपर: zerabyte88',
        ar: 'المطور: zerabyte88',
        fr: 'Développeur : zerabyte88',
        ru: 'Разработчик: zerabyte88',
      );

  String get creatorMaintainer => _t(
        en: 'Creator & Maintainer',
        id: 'Pencipta & Pengelola',
        zh: '创建者与维护者',
        es: 'Creador y mantenedor',
        pt: 'Criador e mantenedor',
        ja: '作成者・メンテナー',
        ko: '제작자 및 관리자',
        hi: 'निर्माता और अनुरक्षक',
        ar: 'المنشئ والمشرف',
        fr: 'Créateur et mainteneur',
        ru: 'Создатель и разработчик',
      );

  String get openGitHubProfile => _t(
        en: 'Open GitHub Profile',
        id: 'Buka Profil GitHub',
        zh: '打开 GitHub 主页',
        es: 'Abrir perfil de GitHub',
        pt: 'Abrir perfil no GitHub',
        ja: 'GitHub プロフィールを開く',
        ko: 'GitHub 프로필 열기',
        hi: 'GitHub प्रोफ़ाइल खोलें',
        ar: 'فتح ملف تعريف GitHub',
        fr: 'Ouvrir le profil GitHub',
        ru: 'Открыть профиль GitHub',
      );

  // ── Update Dialog ──────────────────────────────────────────────────────────
  String get newVersionAvailable => _t(
        en: 'A new version of Phantek Gallery is available.',
        id: 'Versi baru Phantek Gallery telah tersedia.',
        zh: 'Phantek Gallery 有新版本可用。',
        es: 'Hay una nueva versión de Phantek Gallery disponible.',
        pt: 'Uma nova versão do Phantek Gallery está disponível.',
        ja: 'Phantek Gallery の新しいバージョンが利用可能です。',
        ko: 'Phantek Gallery의 새 버전을 사용할 수 있습니다.',
        hi: 'Phantek Gallery का नया संस्करण उपलब्ध है।',
        ar: 'يتوفر إصدار جديد من Phantek Gallery.',
        fr: 'Une nouvelle version de Phantek Gallery est disponible.',
        ru: 'Доступна новая версия Phantek Gallery.',
      );

  String get whatsNew => _t(
        en: 'What\'s new:',
        id: 'Yang baru:',
        zh: '更新内容：',
        es: 'Novedades:',
        pt: 'Novidades:',
        ja: '更新内容:',
        ko: '새로운 기능:',
        hi: 'नया क्या है:',
        ar: 'ما الجديد:',
        fr: 'Nouveautés :',
        ru: 'Что нового:',
      );

  String get downloadAndInstall => _t(
        en: 'Download & Install',
        id: 'Unduh & Pasang',
        zh: '下载并安装',
        es: 'Descargar e instalar',
        pt: 'Baixar e instalar',
        ja: 'ダウンロードしてインストール',
        ko: '다운로드 및 설치',
        hi: 'डाउनलोड और इंस्टॉल करें',
        ar: 'تنزيل وتثبيت',
        fr: 'Télécharger et installer',
        ru: 'Скачать и установить',
      );

  String get later => _t(
        en: 'Later',
        id: 'Nanti',
        zh: '稍后',
        es: 'Más tarde',
        pt: 'Mais tarde',
        ja: '後で',
        ko: '나중에',
        hi: 'बाद में',
        ar: 'لاحقاً',
        fr: 'Plus tard',
        ru: 'Позже',
      );

  String get downloading => _t(
        en: 'Downloading…',
        id: 'Mengunduh…',
        zh: '正在下载…',
        es: 'Descargando…',
        pt: 'Baixando…',
        ja: 'ダウンロード中…',
        ko: '다운로드 중…',
        hi: 'डाउनलोड हो रहा है…',
        ar: 'جاري التنزيل…',
        fr: 'Téléchargement…',
        ru: 'Загрузка…',
      );

  String downloadingPercent(int percent) => switch (_lang) {
        'id' => '$percent% terunduh',
        'zh' => '已下载 $percent%',
        'es' => '$percent% descargado',
        'pt' => '$percent% baixado',
        'ja' => '$percent% ダウンロード完了',
        'ko' => '$percent% 다운로드됨',
        'hi' => '$percent% डाउनलोड हुआ',
        'ar' => 'تم تنزيل $percent%',
        'fr' => '$percent % téléchargé',
        'ru' => 'Загружено: $percent%',
        _ => '$percent% downloaded',
      };

  String updateAvailableVersion(String version) => switch (_lang) {
        'id' => 'Pembaruan v$version',
        'zh' => '更新 v$version',
        'es' => 'Actualización v$version',
        'pt' => 'Atualização v$version',
        'ja' => 'アップデート v$version',
        'ko' => '업데이트 v$version',
        'hi' => 'अपडेट v$version',
        'ar' => 'تحديث v$version',
        'fr' => 'Mise à jour v$version',
        'ru' => 'Обновление v$version',
        _ => 'Update v$version',
      };

  String get alreadyUpToDate => _t(
        en: 'Already up to date',
        id: 'Sudah versi terbaru',
        zh: '已是最新版本',
        es: 'Ya está actualizado',
        pt: 'Já está atualizado',
        ja: 'すでに最新です',
        ko: '이미 최신 버전입니다',
        hi: 'पहले से ही नवीनतम संस्करण है',
        ar: 'محدث بالفعل إلى أحدث إصدار',
        fr: 'Déjà à jour',
        ru: 'Уже установлена последняя версия',
      );

  String updateCheckFailed(String error) => switch (_lang) {
        'id' => 'Pemeriksaan pembaruan gagal: $error',
        'zh' => '检查更新失败：$error',
        'es' => 'Error al buscar actualizaciones: $error',
        'pt' => 'Falha ao verificar atualizações: $error',
        'ja' => '更新の確認に失敗しました: $error',
        'ko' => '업데이트 확인 실패: $error',
        'hi' => 'अपडेट जांच विफल: $error',
        'ar' => 'فشل التحقق من التحديث: $error',
        'fr' => 'Échec de la recherche de mise à jour : $error',
        'ru' => 'Сбой проверки обновлений: $error',
        _ => 'Update check failed: $error',
      };

  String get downloadFailed => _t(
        en: 'Download failed. Please try again.',
        id: 'Unduhan gagal. Silakan coba lagi.',
        zh: '下载失败，请重试。',
        es: 'Error en la descarga. Inténtalo de nuevo.',
        pt: 'Falha no download. Tente novamente.',
        ja: 'ダウンロードに失敗しました。もう一度お試しください。',
        ko: '다운로드 실패. 다시 시도해 주세요.',
        hi: 'डाउनलोड विफल। कृपया पुन: प्रयास करें।',
        ar: 'فشل التنزيل. يرجى المحاولة مرة أخرى.',
        fr: 'Échec du téléchargement. Veuillez réessayer.',
        ru: 'Ошибка загрузки. Пожалуйста, попробуйте еще раз.',
      );

  String installFailed(String error) => switch (_lang) {
        'id' => 'Pemasangan gagal: $error',
        'zh' => '安装失败：$error',
        'es' => 'Error de instalación: $error',
        'pt' => 'Falha na instalação: $error',
        'ja' => 'インストールに失敗しました: $error',
        'ko' => '설치 실패: $error',
        'hi' => 'इंस्टॉलेशन विफल: $error',
        'ar' => 'فشل التثبيت: $error',
        'fr' => 'Échec de l\'installation : $error',
        'ru' => 'Сбой установки: $error',
        _ => 'Install failed: $error',
      };

  // Helper string dispatcher
  String _t({
    required String en,
    required String id,
    required String zh,
    required String es,
    required String pt,
    required String ja,
    required String ko,
    required String hi,
    required String ar,
    required String fr,
    required String ru,
  }) {
    return switch (_lang) {
      'id' => id,
      'zh' => zh,
      'es' => es,
      'pt' => pt,
      'ja' => ja,
      'ko' => ko,
      'hi' => hi,
      'ar' => ar,
      'fr' => fr,
      'ru' => ru,
      _ => en,
    };
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => [
        'id',
        'en',
        'zh',
        'es',
        'pt',
        'ja',
        'ko',
        'hi',
        'ar',
        'fr',
        'ru',
      ].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Convenience extension on [BuildContext] to access localized strings.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get tr => AppLocalizations.of(this);
}
