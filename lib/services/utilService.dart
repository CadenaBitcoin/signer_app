import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UtilService {
  static String? selectedLanguage;
  static String? selectedLanguageName;

  static bool firstLaunch = true;

  String toFixed2DecimalPlaces(String? data, {int decimalPlaces = 2}) {
    if (data != null && data != 'null') {
      data = Decimal.parse(data).toString();
      List<String> values = data.split('.');
      if (values.length == 2 && values[1].length > decimalPlaces) {
        return values[0] + '.' + values[1].substring(0, decimalPlaces);
      } else {
        return data.toString();
      }
    }
    return '0';
  }

  String toFixed2DecimalPlaces2(String? data, {int decimalPlaces = 2}) {
    if (data != null && data != 'null') {
      try {
        Decimal parsedValue = Decimal.parse(data);
        String roundedValue = parsedValue.toDouble().toStringAsFixed(decimalPlaces); // Ensure proper rounding

        List<String> values = roundedValue.split('.');
        if (values.length == 2 && values[1].length == decimalPlaces) {
          // Add thousand separators and preserve the decimal part
          return values[0].replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},') + '.' + values[1];
        } else {
          return values[0].replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
        }
      } catch (e) {
        print('Error parsing data: ${e.runtimeType}');
        return '0';
      }
    }
    return '0';
  }

  // Future<void> copyToClipboard(String copiedText, {String? title}) async {
  //   await Clipboard.setData(ClipboardData(text: copiedText));
  //   showToast(title ?? "Copied to clipboard", title: "Message");
  //   // Fluttertoast.showToast(
  //   //     msg: "Copied to clipboard",
  //   //     toastLength: Toast.LENGTH_SHORT,
  //   //     gravity: ToastGravity.CENTER,
  //   //     timeInSecForIosWeb: 1,
  //   //     backgroundColor: Color(0xFF00D339),
  //   //     textColor: Colors.white,
  //   //     fontSize: 16.0);
  // }

  // showToast(message, {Color color = Colors.red}) {
  //   Fluttertoast.showToast(
  //       msg: "$message",
  //       toastLength: Toast.LENGTH_SHORT,
  //       gravity: ToastGravity.CENTER,
  //       timeInSecForIosWeb: 1,
  //       backgroundColor: color,
  //       textColor: Colors.white,
  //       fontSize: 16.0);
  // }

  static bool deviceSizeAbove750(context) {
    Size size = MediaQuery.of(context).size;
    if (size.height > 750) {
      return true;
    } else {
      return false;
    }
  }

  static bool deviceSizeAbove800(context) {
    Size size = MediaQuery.of(context).size;
    if (size.height > 800) {
      return true;
    } else {
      return false;
    }
  }

  static bool deviceSizeAbove850(context) {
    Size size = MediaQuery.of(context).size;
    if (size.height > 850) {
      return true;
    } else {
      return false;
    }
  }

  static bool deviceWidthSizeAbove400(context) {
    Size size = MediaQuery.of(context).size;
    print("size.width ${size.width}");
    if (size.width > 400) {
      return true;
    } else {
      return false;
    }
  }

  // void launchURL(BuildContext context, url) async {
  //   try {
  //     await launchUrl(Uri.parse(url));
  //   } catch (e) {
  //     // An exception is thrown if browser app is not installed on Android device.
  //     debugPrint(e.toString());
  //   }
  // }

  void getLanguage() async {
    SharedPreferences _prefs = await SharedPreferences.getInstance();
    selectedLanguage = _prefs.getString('SELECTED_LANGUAGE') ?? 'uk';
    print("getStatic $selectedLanguage");
  }
}

RegExp lowerCase = new RegExp(r"(?=.*[a-z])\w+");
RegExp upperCase = new RegExp(r"(?=.*[A-Z])\w+");
RegExp containsNumber = new RegExp(r"(?=.*?[0-9])");
RegExp hasSpecialCharacters = new RegExp(r'[@$!%*?&#^()_\-]');
