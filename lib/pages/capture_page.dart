import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiao_ei_data_capture/shared/variables.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({Key? key}) : super(key: key);

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  final FlutterBlue flutterBlue = FlutterBlue.instance;

  TextEditingController labelController = TextEditingController();
  String _label = '';
  String _duration = "1";
  String _sensorType = "3";

  BluetoothDevice? device;
  BluetoothCharacteristic? rx;
  BluetoothCharacteristic? tx;
  bool _connected = false;
  bool _hasProject = false;
  bool _found = false;
  bool _sampling = false;
  bool _bleOn = false;
  String? _eiApiKey;
  String? _hmacKey;

  var values = [];

  @override
  void initState() {
    super.initState();

    if (kDebugMode) {
      print("inside initState");
    }
    flutterBlue.isOn.then((value) => {
          if (mounted)
            {
              setState(() {
                _bleOn = value;
              })
            }
        });

    flutterBlue.startScan(
        withServices: [Guid(serviceUUID.toLowerCase())],
        timeout: const Duration(seconds: 4),
        allowDuplicates: false);

    flutterBlue.scanResults.listen((results) async {
      // do something with scan results
      for (ScanResult r in results) {
        if (r.device.name == bleName) {
          await flutterBlue.stopScan();
          device = r.device;

          if (mounted) {
            setState(() {
              _found = true;
              if (kDebugMode) {
                print("Found BLE device");
              }
            });
          }
        }
      }
    });

    _prefs.then((SharedPreferences prefs) {
      _eiApiKey = prefs.getString('eiApiKey') ?? "";

      if (mounted) {
        setState(() {
          if (_eiApiKey != "") {
            _hasProject = true;
          }
          _hmacKey = prefs.getString('hmacKey') ?? "";
        });
      }
    });
  }

  @override
  void deactivate() async {
    super.deactivate();
    await device?.disconnect();
    if (kDebugMode) {
      print("inside deactivate");
    }
  }

  @override
  Widget build(BuildContext context) {
    double containerWidth = MediaQuery.of(context).size.width * 1.0;

    return Column(
      children: [
        if (!_bleOn)
          const Padding(
            padding: EdgeInsets.all(10.0),
            child: Text(
              "Bluetooth is turned off. Please turn it on.",
              style: TextStyle(fontSize: fontSizeSmall),
            ),
          ),
        if (_bleOn && _found && !_connected)
          Center(
            child: ElevatedButton(
              onPressed: () async {
                try {
                  await device?.connect();

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('BLE connected.')),
                  );
                  if (kDebugMode) {
                    print("connected to BLE device");
                  }

                  List<BluetoothService>? services =
                      await device?.discoverServices();

                  setState(() {
                    _connected = true;
                  });
                  services?.forEach((service) async {
                    if (service.uuid.toString() == serviceUUID.toLowerCase()) {
                      if (kDebugMode) {
                        print("Discovering characteristics...");
                      }

                      var characteristics = service.characteristics;
                      for (BluetoothCharacteristic c in characteristics) {
                        if (c.uuid.toString() == rxUUID.toLowerCase()) {
                          if (kDebugMode) {
                            print("Found needed RX characteristic");
                          }
                          rx = c;
                          await rx?.setNotifyValue(true);
                          rx?.value.listen((value) async {
                            String strData = String.fromCharCodes(value);
                            // print("value received ${strData}");
                            if (strData == ";") {
                              if (kDebugMode) {
                                print(
                                    "### Sampling data received with ${values.length} samples");
                              }
                              await postDataToEI(_label);
                            } else if (strData != "") {
                              final s = strData.split(",");

                              if (_sensorType == "3") {
                                values.add([
                                  double.parse(s[1]),
                                  double.parse(s[2]),
                                  double.parse(s[3])
                                ]);
                              } else if (_sensorType == "6") {
                                values.add([
                                  double.parse(s[1]),
                                  double.parse(s[2]),
                                  double.parse(s[3]),
                                  double.parse(s[4]),
                                  double.parse(s[5]),
                                  double.parse(s[6])
                                ]);
                              }
                            }
                          });
                        }

                        if (c.uuid.toString() == txUUID.toLowerCase()) {
                          tx = c;
                        }
                      }
                    }
                  });
                } catch (e) {
                  flutterBlue.startScan(
                      withServices: [Guid(serviceUUID.toLowerCase())],
                      timeout: const Duration(seconds: 4),
                      allowDuplicates: false);
                }
              }, //onPressed
              child: const Text('Connect to BLE'),
            ),
          ),
        if (_connected)
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                primary: Colors.blueGrey, // background
                onPrimary: Colors.white, // foreground
              ),
              child: const Text('Disconnect BLE'),
              onPressed: () async {
                await device?.disconnect();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('BLE disconnected.')),
                );
                setState(() {
                  _connected = false;
                });
              },
            ),
          ),
        if (_hasProject && _connected)
          Center(
              child: Card(
                  color: const Color.fromARGB(255, 240, 237, 237),
                  margin: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: containerWidth,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(children: [
                        const Padding(
                          padding: EdgeInsets.all(10.0),
                          child: Text(
                            "Data Acquisition",
                            style: TextStyle(fontSize: fontSizeBig),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.all(10.0),
                          child: Text(
                            "Accelerometer data captured at 50Hz.",
                            style: TextStyle(fontSize: fontSizeSmall),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10.0),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                                border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(4.0)),
                            )),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _sensorType,
                                isDense: true,
                                isExpanded: true,
                                onChanged: (String? newValue) {
                                  setState(() {
                                    _sensorType = newValue!;
                                  });
                                },
                                items: <String>[
                                  '3',
                                  '6',
                                ].map<DropdownMenuItem<String>>((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text('$value axis accelerometer'),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10.0),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                                border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(4.0)),
                            )),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _duration,
                                isDense: true,
                                isExpanded: true,
                                onChanged: (String? newValue) {
                                  setState(() {
                                    _duration = newValue!;
                                  });
                                },
                                items: <String>[
                                  '1',
                                  '2',
                                  '3',
                                  '4',
                                  '5'
                                ].map<DropdownMenuItem<String>>((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text('$value second(s)'),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                        TextField(
                          controller: labelController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Label',
                          ),
                          onChanged: (text) {
                            setState(() {
                              _label = text.trim();
                              //you can access nameController in its scope to get
                              // the value of text entered as shown below
                              //fullName = nameController.text;
                            });
                          },
                        ),
                        if (_sampling)
                          const Center(
                              child: Padding(
                            padding: EdgeInsets.all(10.0),
                            child: CircularProgressIndicator(),
                          )),
                        ElevatedButton(
                          child: const Text('Start sampling'),
                          onPressed: _label != "" && !_sampling
                              ? () {
                                  values = [];
                                  tx?.write("S$_duration".codeUnits);
                                  setState(() {
                                    _sampling = true;
                                  });
                                }
                              : null,
                        ),
                      ]),
                    ),
                  ))),
        if (!_hasProject)
          Center(
              child: Card(
                  color: const Color.fromARGB(255, 240, 237, 237),
                  margin: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: containerWidth,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(children: const [
                        Text(
                          "No project is linked. Steup your Edge Impuls project first on Setup page.",
                          style: TextStyle(fontSize: fontSizeSmall),
                        )
                      ]),
                    ),
                  ))),
      ],
    );
  }

  postDataToEI(String label) async {
    if (kDebugMode) {
      print("call EI with $_hmacKey and $_eiApiKey");
    }
    final String response = await rootBundle
        .loadString('assets/data/accelerometer${_sensorType}axis.json');
    final jsonData = await json.decode(response);

    var hmacSha256 = Hmac(sha256, utf8.encode(_hmacKey!)); // HMAC-SHA256
    jsonData['payload']['values'] = values;
    var digest = hmacSha256.convert(utf8.encode(jsonEncode(jsonData)));
    jsonData['signature'] = digest.toString();
    final r = await http.post(
      Uri.parse('https://ingestion.edgeimpulse.com/api/training/data'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'x-api-key': _eiApiKey!,
        'x-file-name': '$label.json',
        'x-label': label,
      },
      body: utf8.encode(jsonEncode(jsonData)),
    );
    setState(() {
      _sampling = false;
    });
    if (r.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sampling data uploaded successfully.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error.')),
      );
    }
    values = [];
  }
}
