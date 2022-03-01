import 'package:flutter/material.dart';
import 'package:xiao_ei_data_capture/pages/capture_page.dart';
import 'package:xiao_ei_data_capture/pages/setup_page.dart';
import 'package:flutter_blue/flutter_blue.dart';

void main() {
  runApp(const MaterialApp(home: XiaoDataCaptureApp()));
}

class XiaoDataCaptureApp extends StatefulWidget {
  const XiaoDataCaptureApp({Key? key}) : super(key: key);

  @override
  State<XiaoDataCaptureApp> createState() => _XiaoDataCaptureAppState();
}

class _XiaoDataCaptureAppState extends State<XiaoDataCaptureApp>
    with SingleTickerProviderStateMixin {
  // This widget is the root of your application.
  // We need a TabController to control the selected tab programmatically
  late TabController controller;

  @override
  void initState() {
    super.initState();
    controller = TabController(vsync: this, length: 2);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('EI Blue'),
          // Use TabBar to show the three tabs
        ),
        bottomNavigationBar: Material(
            color: Colors.blueAccent,
            child: TabBar(controller: controller, tabs: <Tab>[
              Tab(text: "Setup", icon: Icon(Icons.settings_rounded)),
              Tab(text: "Capture", icon: Icon(Icons.cloud_upload_rounded)),
            ])),
        body: TabBarView(
            controller: controller,
            children: <Widget>[SetupPage(), CapturePage()]));
  }
}
