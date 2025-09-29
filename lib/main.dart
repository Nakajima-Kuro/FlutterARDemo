import 'package:flutter/material.dart';
import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:vector_math/vector_math_64.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(debugShowCheckedModeBanner: false, home: ARHome());
  }
}

class ARHome extends StatefulWidget {
  const ARHome({super.key});

  @override
  State<ARHome> createState() => _ARHomeState();
}

class _ARHomeState extends State<ARHome> {
  ARSessionManager? _sessionManager;
  ARObjectManager? _objectManager;
  ARAnchorManager? _anchorManager;

  final List<ARNode> _nodes = [];
  final List<ARAnchor> _anchors = [];

  @override
  void dispose() {
    _sessionManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ARView(
          planeDetectionConfig: PlaneDetectionConfig.horizontal,
          onARViewCreated: _onARViewCreated,
        ),
      ),
      floatingActionButton: _anchors.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _removeEverything,
              label: const Text('Clear Scene'),
              icon: const Icon(Icons.delete_outline),
            )
          : null,
    );
  }

  Future<void> _onARViewCreated(
    ARSessionManager sessionManager,
    ARObjectManager objectManager,
    ARAnchorManager anchorManager,
    ARLocationManager locationManager,
  ) async {
    _sessionManager = sessionManager;
    _objectManager = objectManager;
    _anchorManager = anchorManager;

    await _sessionManager!.onInitialize(
      showFeaturePoints: false,
      showPlanes: true,
      customPlaneTexturePath: null,
      showWorldOrigin: false,
    );

    await _objectManager!.onInitialize();
    _sessionManager!.onPlaneOrPointTap = _handlePlaneTap;
  }

  Future<void> _handlePlaneTap(List<ARHitTestResult> hits) async {
    if (hits.isEmpty) return;

    // Only consider the closest hit on the plane
    final planeHit = hits.firstWhere(
      (hit) => hit.type == ARHitTestResultType.plane,
      orElse: () => hits.first,
    );

    // Add an anchor to the hit position
    final anchor = ARPlaneAnchor(transformation: planeHit.worldTransform);
    final didAddAnchor = await _anchorManager!.addAnchor(anchor) ?? false;
    if (!didAddAnchor) return;

    _anchors.add(anchor);

    // Add a node with Model to the anchor
    final node = ARNode(
      type: NodeType.localGLTF2,
      uri: 'assets/models/duck/Duck.gltf',
      scale: Vector3.all(0.2),
      position: Vector3.zero(),
      rotation: Vector4(1.0, 0.0, 0.0, 1.0),
    );

    // Check if adding a node was successful. Otherwise remove the anchor
    final didAddNode =
        await _objectManager!.addNode(node, planeAnchor: anchor) ?? false;
    if (!didAddNode) {
      await _anchorManager!.removeAnchor(anchor);
      _anchors.remove(anchor);
      return;
    }

    _nodes.add(node);
    setState(() {});
  }

  Future<void> _removeEverything() async {
    for (final node in List<ARNode>.from(_nodes)) {
      await _objectManager!.removeNode(node);
      _nodes.remove(node);
    }

    for (final anchor in List<ARAnchor>.from(_anchors)) {
      await _anchorManager!.removeAnchor(anchor);
      _anchors.remove(anchor);
    }

    setState(() {});
  }
}
