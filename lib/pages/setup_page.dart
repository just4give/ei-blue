import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:xiao_ei_data_capture/shared/variables.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({Key? key}) : super(key: key);

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  String? _eiApiKey;
  bool hasProject = false;
  String? _projectId;
  String? _projectName;
  String? _projectOwner;

  @override
  void initState() {
    super.initState();

    _prefs.then((SharedPreferences prefs) {
      _eiApiKey = prefs.getString('eiApiKey') ?? "";

      setState(() {
        if (_eiApiKey != "") {
          hasProject = true;
        }
        _projectId = prefs.getString('projectId') ?? "";
        _projectName = prefs.getString('projectName') ?? "";
        _projectOwner = prefs.getString('projectOwner') ?? "";
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    double containerWidth = MediaQuery.of(context).size.width * 1.0;
    return Column(
      children: [
        if (hasProject)
          Center(
            child: Card(
              color: const Color.fromARGB(255, 240, 237, 237),
              margin: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: containerWidth,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 25),
                        child: Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 50,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            "ID:  $_projectId",
                            style: const TextStyle(fontSize: fontSizeMedium),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              "Name: $_projectName",
                              style: const TextStyle(fontSize: fontSizeMedium),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            "Owner:  $_projectOwner",
                            style: const TextStyle(fontSize: fontSizeMedium),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          Center(
            child: Card(
              color: const Color.fromARGB(255, 240, 237, 237),
              margin: EdgeInsets.all(16.0),
              child: Container(
                width: double.infinity,
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Column(
                    children: const [
                      Padding(
                        padding: EdgeInsets.only(bottom: 25),
                        child: Icon(
                          Icons.error,
                          color: Colors.red,
                          size: 50,
                        ),
                      ),
                      Text(
                        "No project is linked. Navigate to devices page on edge impulse studio and connect a new device. Choose your mobile phone which will show the QR code. Scan the code by tapping below Scan QR Code button.",
                        style: TextStyle(fontSize: fontSizeMedium),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        Center(
          child: ElevatedButton(
            onPressed: () async {
              final data = await Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const QRViewExample(),
              ));

              await getEIProjectInfo(data);
            },
            child: const Text('Scan QR Code'),
          ),
        )
      ],
    );
  }

  getEIProjectInfo(apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    final response = await http.get(
        Uri.parse('https://studio.edgeimpulse.com/v1/api/projects'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
        });

    if (kDebugMode) {
      print(response.statusCode);
    }
    if (kDebugMode) {
      print(response.body);
    }

    if (response.statusCode == 200) {
      var jsonData = json.decode(response.body);
      var id = jsonData["projects"][0]["id"];
      var name = jsonData["projects"][0]["name"];
      var owner = jsonData["projects"][0]["owner"];
      await prefs.setString('projectId', "$id");
      await prefs.setString('projectName', name);
      await prefs.setString('projectOwner', owner);
      await getEIKeys(apiKey, id);

      setState(() {
        hasProject = true;
        _projectId = "$id";
        _projectName = name;
        _projectOwner = owner;
      });
    }
  }
}

getEIKeys(apiKey, projectId) async {
  final prefs = await SharedPreferences.getInstance();
  final response = await http.get(
      Uri.parse('https://studio.edgeimpulse.com/v1/api/${projectId}/devkeys'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
      });

  if (kDebugMode) {
    print(response.statusCode);
  }
  if (kDebugMode) {
    print(response.body);
  }

  if (response.statusCode == 200) {
    var jsonData = json.decode(response.body);
    var hmacKey = jsonData["hmacKey"];
    await prefs.setString('hmacKey', hmacKey);
  }
}

class QRViewExample extends StatefulWidget {
  const QRViewExample({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _QRViewExampleState();
}

class _QRViewExampleState extends State<QRViewExample> {
  Barcode? result;
  bool scanned = false;
  QRViewController? controller;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  String? eiApiKey;

  // In order to get hot reload to work we need to pause the camera if the platform
  // is android, or resume the camera if the platform is iOS.
  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      controller!.pauseCamera();
    }
    controller!.resumeCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          Expanded(flex: 1, child: _buildQrView(context)),
          if (scanned)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(10.0),
                child: Text(
                  "QR Code was scanned successfully. Tap on Done button below.",
                  style: TextStyle(fontSize: fontSizeMedium),
                ),
              ),
            ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 50, bottom: 100),
              child: SizedBox(
                width: 100,
                child: ElevatedButton(
                  onPressed: scanned
                      ? () {
                          Navigator.pop(context, eiApiKey);
                        }
                      : null,
                  child: const Text('Done'),
                  style: ElevatedButton.styleFrom(
                    primary: Colors.blueAccent, // background
                    onPrimary: Colors.white, // foreground
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildQrView(BuildContext context) {
    // For this example we check how width or tall the device is and change the scanArea and overlay accordingly.
    var scanArea = (MediaQuery.of(context).size.width < 400 ||
            MediaQuery.of(context).size.height < 400)
        ? 150.0
        : 300.0;
    // To ensure the Scanner view is properly sizes after rotation
    // we need to listen for Flutter SizeChanged notification and update controller
    return QRView(
      key: qrKey,
      onQRViewCreated: _onQRViewCreated,
      overlay: QrScannerOverlayShape(
          borderColor: Colors.red,
          borderRadius: 10,
          borderLength: 30,
          borderWidth: 10,
          cutOutSize: scanArea),
      onPermissionSet: (ctrl, p) => _onPermissionSet(context, ctrl, p),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    setState(() {
      this.controller = controller;
    });
    controller.scannedDataStream.listen((scanData) async {
      if (scanData != null) {
        String? scannedUrl = scanData.code;

        if (scannedUrl?.indexOf("https://smartphone.edgeimpulse.com") != -1) {
          eiApiKey = Uri.parse(scannedUrl!).queryParameters["apiKey"];
          if (kDebugMode) {
            print("$eiApiKey");
          }
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('eiApiKey', eiApiKey!);
          controller.dispose();

          setState(() {
            scanned = true;
          });
        }
      }
    });
  }

  void _onPermissionSet(BuildContext context, QRViewController ctrl, bool p) {
    log('${DateTime.now().toIso8601String()}_onPermissionSet $p');
    if (!p) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('no Permission')),
      );
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}
