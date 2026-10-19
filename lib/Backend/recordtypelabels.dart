String recordTypeLabel(String? recordType) {
  switch (recordType) {
    case 'single':
      return '• Single';
    case 'ep':
      return '• EP';
    case 'compile':
      return '• Compilation';
    case 'album':
    default:
      return '';
  }
}