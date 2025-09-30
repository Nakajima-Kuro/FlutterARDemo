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
      if (node != null) {
        _nodes.add(node);
      } else {
        await _anchorManager?.removeAnchor(anchorA);
        await _anchorManager?.removeAnchor(anchorB);
        _anchors.remove(anchorA);
        _anchors.remove(anchorB);
      }
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
    required double depthM,
    double diameterM = 0.2,
    String uri = 'assets/models/cylinder/cylinder.gltf',
  }) async {
    assert(depthM >= 0, 'depthM must be non-negative');

    final aWorld = anchorA.transformation.getTranslation();
    final bWorld = anchorB.transformation.getTranslation();
    final segmentWorld = bWorld - aWorld;
    final segmentLength = segmentWorld.length;
    final minLength = math.max(depthM, 0.05);
    if (segmentLength < minLength) return null;

    final midWorld = aWorld + segmentWorld * 0.5;
    final worldToAnchor = Matrix4.copy(anchorA.transformation)..invert();
    final localA = worldToAnchor.transformed3(aWorld.clone());
    final localB = worldToAnchor.transformed3(bWorld.clone());
    final localMid = worldToAnchor.transformed3(midWorld.clone());
    final segmentLocal = localB - localA;
    if (segmentLocal.length2 < 1e-12) return null;

    final directionLocal = segmentLocal.normalized();
    final rotation = Quaternion.fromTwoVectors(
      Vector3(0, 1, 0),
      directionLocal,
    );
    final scale = Vector3(diameterM, segmentLocal.length, diameterM);
    final localTransform = Matrix4.compose(localMid, rotation, scale);

    final node = ARNode(
      type: NodeType.localGLTF2,
      uri: uri,
      transformation: localTransform,
    );

    final didAddNode =
        await objectMgr.addNode(node, planeAnchor: anchorA) ?? false;
    if (!didAddNode) {
      return null;
    }
    return node;
  }

  // Get Vector3 position from an ARAnchor
  Vector3 anchorToVector3(ARAnchor anchor) {
    return anchor.transformation.getTranslation(); // Float32List of length 16
  }
}
