import 'package:flutter/material.dart';
import 'ar_imports.dart';

import 'dart:math' as math;
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
  final List<ARPlaneAnchor> _anchors = [];

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

    // Add a pipe when we have at least two anchors tapped
    if (_anchors.length >= 2) {
      final anchorA = _anchors[_anchors.length - 2];
      final anchorB = _anchors.last;

      final node = await addPipeBetweenAnchors(
        objectMgr: _objectManager!,
        anchorA: anchorA,
        anchorB: anchorB,
        depthM: 0.1,
        uri: 'assets/models/cylinder/cylinder.gltf',
      );
      if (node != null) _nodes.add(node);
    }

    setState(() {});
  }

  Future<void> _removeEverything() async {
    for (final node in List<ARNode>.from(_nodes)) {
      await _objectManager!.removeNode(node);
      _nodes.remove(node);
    }

    for (final anchor in List<ARPlaneAnchor>.from(_anchors)) {
      await _anchorManager!.removeAnchor(anchor);
      _anchors.remove(anchor);
    }

    setState(() {});
  }

  // add pipe directly between two anchors
  Future<ARNode?> addPipeBetweenAnchors({
    required ARObjectManager objectMgr,
    required ARPlaneAnchor anchorA,
    required ARPlaneAnchor anchorB,
    required double depthM, // push below ground
    double diameterM = 0.2,
    String uri = 'assets/models/duck/Duck.gltf',
  }) async {
    // extract positions from anchors
    final Vector3 a = anchorA.transformation.getTranslation();
    final Vector3 b = anchorB.transformation.getTranslation();

    final seg = b - a;
    final len = seg.length;
    if (len < 0.05) return null; // ignore tiny

    final mid = (a + b) * 0.5;
    final rot = _rotFromY(seg);

    final node = ARNode(
      type: NodeType.localGLTF2,
      uri: uri,
      position: Vector3(mid.x, -depthM, mid.z), // center, pushed down
      rotation: Vector4(rot.x, rot.y, rot.z, rot.w), // orient along segment
      scale: Vector3(diameterM, len, diameterM), // scale to length/diameter
    );

    // Check if adding a node was successful. Otherwise remove the anchor and return null
    final didAddNode =
        await _objectManager!.addNode(node, planeAnchor: anchorA) ?? false;
    if (!didAddNode) {
      await _anchorManager!.removeAnchor(anchorA);
      await _anchorManager!.removeAnchor(anchorB);
      _anchors.remove(anchorA);
      _anchors.remove(anchorB);
      return null;
    }
    return node;
  }

  // Rotate a Y-up unit cylinder to point along `dir`
  Quaternion _rotFromY(Vector3 dir) {
    final y = Vector3(0, 1, 0);
    final d = dir.normalized();
    final dot = y.dot(d).clamp(-1.0, 1.0);
    if (dot > 0.9999) return Quaternion.identity();
    if (dot < -0.9999) return Quaternion.axisAngle(Vector3(1, 0, 0), math.pi);
    final axis = y.cross(d)..normalize();
    final angle = math.acos(dot);
    return Quaternion.axisAngle(axis, angle);
  }

  // Get Vector3 position from an ARAnchor
  Vector3 anchorToVector3(ARAnchor anchor) {
    return anchor.transformation.getTranslation(); // Float32List of length 16
  }
}
