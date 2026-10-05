import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
