String normalizeAccountLinkCode(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');

bool isValidAccountLinkCode(String value) =>
    RegExp(r'^[0-9A-F]{6}$').hasMatch(normalizeAccountLinkCode(value));
