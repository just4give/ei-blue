import 'dart:async';
import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

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
  String _label = "rest";
  String _duration = "3";
  String _sensorType = "3";
  String _3axisJSONString = "";
  String _6axisJSONString = "";
  String _boardType = "microbit";

  BluetoothDevice? device;
  BluetoothCharacteristic? rx;
  BluetoothCharacteristic? tx;
  StreamSubscription? charSubscription;

  bool _connected = false;
  bool _hasProject = false;
  bool _found = false;
  bool _sampling = false;
  bool _uploading = false;
  bool _bleOn = false;
  String? _eiApiKey;
  String? _hmacKey;

  var values = [];
  var row = [];
  int dataCounter = 0;

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
        timeout: const Duration(seconds: 10),
        allowDuplicates: false);

    flutterBlue.scanResults.listen((results) async {
      // do something with scan results
      for (ScanResult r in results) {
        if (kDebugMode) {
          print(r);
        }

        if (r.device.name == bleName || r.device.name == "Arduino") {
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
    await handleDisconnect();
    if (kDebugMode) {
      print("inside deactivate");
    }
  }

  @override
  Widget build(BuildContext context) {
    double containerWidth = MediaQuery.of(context).size.width * 1.0;

    return SingleChildScrollView(
      child: Column(
        children: [
          if (_bleOn && !_found) ...[
            const Padding(
              padding: EdgeInsets.all(10.0),
              child: Text(
                "Searching for your device with name EIBLUE. Make sure your device is powered on and reachable.",
                style: TextStyle(fontSize: fontSizeSmall),
              ),
            ),
            const Center(
                child: Padding(
              padding: EdgeInsets.all(10.0),
              child: CircularProgressIndicator(),
            )),
            Center(
              child: ElevatedButton(
                child: const Text('Re-Scan'),
                onPressed: () async {
                  flutterBlue.startScan(
                      withServices: [Guid(serviceUUID.toLowerCase())],
                      timeout: const Duration(seconds: 4),
                      allowDuplicates: false);
                },
              ),
            ),
          ],
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

                    await loadJSONfromAssets();

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
                      if (service.uuid.toString() ==
                          serviceUUID.toLowerCase()) {
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
                            charSubscription = rx?.value.listen((value) async {
                              if (_boardType == "microbit") {
                                int x = bytesToInteger(value).toInt();
                                if (x > 2048) {
                                  x = (x - 5000) * -1;
                                }

                                if (x == -4999) {
                                  if (kDebugMode) {
                                    print(
                                        "### Sampling data received with ${values.length} samples");
                                  }

                                  if (values.length ==
                                      int.parse(_duration) * 50) {
                                    await postDataToEI(_label);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          backgroundColor: Colors.deepOrange,
                                          content:
                                              Text('Incomplete sampling data')),
                                    );
                                    setState(() {
                                      _sampling = false;
                                      _uploading = false;
                                    });
                                  }
                                } else if (x != 0) {
                                  setState(() {
                                    _uploading = true;
                                    _sampling = false;
                                  });
                                  int r = dataCounter % 3;

                                  row.add(x);
                                  if (r == 2) {
                                    values.add(row);
                                    row = [];
                                  }

                                  dataCounter++;
                                }
                              } else if (_boardType == "xiao") {
                                String strData = String.fromCharCodes(value);
                                if (kDebugMode) {
                                  print("value received ${strData}");
                                }
                                if (strData == ";") {
                                  if (kDebugMode) {
                                    print(
                                        "### Sampling data received with ${values.length} samples");
                                  }
                                  if (values.length ==
                                      int.parse(_duration) * 50) {
                                    //await postDataToEI(_label);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          backgroundColor: Colors.deepOrange,
                                          content:
                                              Text('Incomplete sampling data')),
                                    );
                                    setState(() {
                                      _sampling = false;
                                    });
                                  }
                                } else if (strData != "") {
                                  setState(() {
                                    _sampling = true;
                                  });

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
                  await handleDisconnect();
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
                                  value: _boardType,
                                  isDense: true,
                                  isExpanded: true,
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      _boardType = newValue!;
                                    });
                                  },
                                  items: <String>[
                                    'microbit',
                                    'xiao',
                                  ].map<DropdownMenuItem<String>>(
                                      (String value) {
                                    return DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(value),
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
                                  ].map<DropdownMenuItem<String>>(
                                      (String value) {
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
                                  items: <String>['1', '2', '3', '4', '5']
                                      .map<DropdownMenuItem<String>>(
                                          (String value) {
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
                          if (_sampling && !_uploading)
                            const Center(
                                child: Padding(
                              padding: EdgeInsets.all(10.0),
                              child: CircularProgressIndicator(
                                color: Colors.red,
                              ),
                            )),
                          if (_uploading && !_sampling)
                            const Center(
                                child: Padding(
                              padding: EdgeInsets.all(10.0),
                              child: CircularProgressIndicator(
                                color: Colors.green,
                              ),
                            )),
                          ElevatedButton(
                            child: const Text('Start sampling'),
                            onPressed: _label != "" && !_sampling && !_uploading
                                ? () {
                                    if (kDebugMode) {
                                      print('Start sampling');
                                    }
                                    values = [];
                                    row = [];
                                    dataCounter = 0;

                                    if (_boardType == "microbit") {
                                      tx?.write("$_duration".codeUnits);
                                    } else {
                                      tx?.write("S$_duration".codeUnits);
                                    }

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
      ),
    );
  }

  Future<void> handleDisconnect() async {
    await charSubscription?.cancel();
    await device?.disconnect();
  }

  num bytesToInteger(List<int> bytes) {
    num value = 0;

    for (var i = 0, length = bytes.length; i < length; i++) {
      value += bytes[i] * pow(256, i);
    }

    return value;
  }

  postDataToEI(String label) async {
    if (kDebugMode) {
      print("call EI with $_hmacKey and $_eiApiKey");
    }
    String response = "";
    if (_sensorType == "3") {
      response = _3axisJSONString;
    } else {
      response = _6axisJSONString;
    }
    final jsonData = await json.decode(response);

    var hmacSha256 = Hmac(sha256, utf8.encode(_hmacKey!)); // HMAC-SHA256
    jsonData['payload']['values'] = values;
    var digest = hmacSha256.convert(utf8.encode(jsonEncode(jsonData)));
    jsonData['signature'] = digest.toString();

    if (kDebugMode) {
      print(jsonData);
    }

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
      _uploading = false;
    });
    if (r.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            backgroundColor: Colors.green,
            content: Text('Sampling data uploaded successfully.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            backgroundColor: Colors.deepOrange, content: Text('Error.')),
      );
    }
    values = [];
  }

  Future<void> loadJSONfromAssets() async {
    _3axisJSONString =
        await rootBundle.loadString('assets/data/accelerometer3axis.json');

    _6axisJSONString =
        await rootBundle.loadString('assets/data/accelerometer6axis.json');
  }
}
