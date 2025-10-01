import 'package:flutter/material.dart';
import 'ar_imports.dart';

import 'package:vector_math/vector_math_64.dart';

class PipeModelUri {
  //You can add other pipe models here for other colors
  static const defaultCylinder = 'assets/models/cylinder/default.gltf';
  static const blueCylinder = 'assets/models/cylinder/blue.gltf';
}

const _depthGuideModelUri = 'assets/models/cube/cube.gltf';

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

// Bundles the midpoint anchor with its pipe node for easier cleanup.
class _PipeSegment {
  const _PipeSegment({required this.anchor, required this.node});

  final ARPlaneAnchor anchor;
  final ARNode node;
}

class _ARHomeState extends State<ARHome> {
  ARSessionManager? _sessionManager;
  ARObjectManager? _objectManager;
  ARAnchorManager? _anchorManager;

  static const double _defaultPipeDepth = 1.0;

  // Scene nodes for every pipe segment currently placed.
  final List<ARNode> _nodes = [];
  // Tap anchors the user drops on the detected plane.
  final List<ARPlaneAnchor> _anchors = [];
  // Midpoint anchors that keep each pipe steady under the plane.
  final List<ARPlaneAnchor> _midAnchors = [];
  // Thin guideline nodes hanging from each tap anchor for depth perception.
  final Map<String, List<ARNode>> _guideNodes = {};

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

    // Add or refresh the depth guide hanging from this anchor.
    await _addDepthGuideForAnchor(anchor, depthM: _defaultPipeDepth);

    // Add a pipe when we have at least two anchors tapped
    if (_anchors.length >= 2) {
      final anchorA = _anchors[_anchors.length - 2];
      final anchorB = _anchors.last;

      // Build a pipe between the two most recent tap anchors.
      final segment = await addPipeBetweenAnchors(
        objectMgr: _objectManager!,
        anchorA: anchorA,
        anchorB: anchorB,
        depthM: _defaultPipeDepth,
        uri: PipeModelUri.blueCylinder,
      );
      if (segment != null) {
        // Track the pipe node and its midpoint anchor so we can clean up later.
        _nodes.add(segment.node);
        _midAnchors.add(segment.anchor);
      } else {
        await _removeTapAnchors(<ARPlaneAnchor>[anchorA, anchorB]);
      }
    }

    setState(() {});
  }

  /// Adds a depth guide consisting of a series of cylinders to the scene,
  /// hanging from the given anchor and extending to the given depth.
  ///
  /// The depth guide is built by first calculating the spacing between each
  /// guide segment based on the given depth. Then, it builds each segment by
  /// creating a local transformation matrix that positions the segment at the
  /// calculated center Y position and scales it to the guide diameter and
  /// segment length.
  ///
  /// Each segment is added to the scene under the given anchor, and the
  /// resulting nodes are tracked so that they can be cleaned up later.
  ///
  /// If the depth is not positive, the function will remove any existing depth
  /// guide for the given anchor.
  ///
  /// The function will return early if the object manager is null, or if
  /// adding any of the nodes to the scene fails.
  Future<void> _addDepthGuideForAnchor(
    ARPlaneAnchor anchor, {
    required double depthM,
  }) async {
    final objectMgr = _objectManager;
    if (objectMgr == null) return;
    if (depthM <= 0) {
      _removeDepthGuidesForAnchor(anchor);
      return;
    }

    _removeDepthGuidesForAnchor(anchor);

    const guideDiameter = 0.01;
    const segments = 1;
    final spacing = depthM / segments;
    final segmentLength = spacing * 0.6;
    final nodes = <ARNode>[];

    for (var i = 0; i < segments; i++) {
      final centerY = -spacing * (i + 0.5);
      final localTransform = Matrix4.compose(
        Vector3(0, centerY, 0),
        Quaternion(0, 0, 0, 1),
        Vector3(guideDiameter, segmentLength, guideDiameter),
      );
      final node = ARNode(
        type: NodeType.localGLTF2,
        uri: _depthGuideModelUri,
        transformation: localTransform,
      );

      if (await objectMgr.addNode(node, planeAnchor: anchor) != true) {
        for (final added in nodes) {
          objectMgr.removeNode(added);
        }
        return;
      }
      nodes.add(node);
    }

    if (nodes.isNotEmpty) {
      _guideNodes[anchor.name] = nodes;
    }
  }

  void _removeDepthGuidesForAnchor(ARPlaneAnchor anchor) {
    _removeDepthGuidesByName(anchor.name);
  }

  void _removeDepthGuidesByName(String anchorName) {
    final nodes = _guideNodes.remove(anchorName);
    if (nodes == null) return;
    final objectMgr = _objectManager;
    for (final node in nodes) {
      objectMgr?.removeNode(node);
    }
  }

  /// Build a pipe between two anchors in world space and add it to the scene.
  ///
  /// The pipe is constructed by first measuring the tap anchors in world space and
  /// sinking them by [depthM]. Then, it creates a midpoint anchor by reusing
  /// [anchorA]'s orientation at the segment's center, and uses this midpoint
  /// anchor to convert both tap positions into the midpoint anchor's local space.
  ///
  /// The pipe is then built using the computed local transform, and added to the scene
  /// under the midpoint anchor.
  ///
  /// If the adjusted segment collapses to avoid zero-length pipes, the function
  /// returns null.
  ///
  /// [objectMgr] is the object manager responsible for adding the pipe node to the scene.
  ///
  /// [anchorA] and [anchorB] are the two anchors in world space which define the endpoints
  /// of the pipe.
  ///
  /// [depthM] is the depth of the pipe in meters.
  ///
  /// [diameterM] is the diameter of the pipe in meters. Defaults to 0.2.
  ///
  /// [uri] is the uri of the pipe model. Defaults to [_pipeModelUri.defaultCylinder].
  ///
  /// Returns a [_PipeSegment] object which contains the midpoint anchor and the pipe node if
  /// successful, or null if the function fails.
  Future<_PipeSegment?> addPipeBetweenAnchors({
    required ARObjectManager objectMgr,
    required ARPlaneAnchor anchorA,
    required ARPlaneAnchor anchorB,
    required double depthM,
    double diameterM = 0.2,
    String uri = PipeModelUri.defaultCylinder,
  }) async {
    assert(depthM >= 0, 'depthM must be non-negative');

    final anchorMgr = _anchorManager;
    if (anchorMgr == null) return null;

    // Measure the tap anchors in world space and sink them by depthM.
    final aWorld = anchorA.transformation.getTranslation();
    final bWorld = anchorB.transformation.getTranslation();
    final depthOffset = _planeNormal(anchorA.transformation) * depthM;
    final adjustedAWorld = aWorld - depthOffset;
    final adjustedBWorld = bWorld - depthOffset;
    final segmentWorld = adjustedBWorld - adjustedAWorld;
    final segmentLengthWorld = segmentWorld.length;
    const minLength = 0.05;
    if (segmentLengthWorld < minLength) return null;

    // Create a midpoint anchor by reusing anchorA's orientation at the segment's center.
    final midWorld = (adjustedAWorld + adjustedBWorld) * 0.5;
    final midTransform = Matrix4.copy(anchorA.transformation)
      ..setTranslation(midWorld);

    final midAnchor = ARPlaneAnchor(transformation: midTransform);
    if (await anchorMgr.addAnchor(midAnchor) != true) {
      return null;
    }

    // Convert both tap positions into the midpoint anchor's local space.
    final worldToMid = Matrix4.copy(midTransform)..invert();
    final localA = worldToMid.transformed3(adjustedAWorld.clone());
    final localB = worldToMid.transformed3(adjustedBWorld.clone());

    final segmentLocal = localB - localA;
    // Abort if the adjusted segment collapses to avoid zero-length pipes.
    if (segmentLocal.length2 < 1e-12) {
      await anchorMgr.removeAnchor(midAnchor);
      return null;
    }

    // Build the pipe transform so the cylinder spans between the two endpoints.
    final localMid = (localA + localB) * 0.5;
    final directionLocal = segmentLocal.normalized();
    final rotation = Quaternion.fromTwoVectors(
      Vector3(0, 1, 0),
      directionLocal,
    );
    final scale = Vector3(diameterM, segmentLocal.length, diameterM);
    final localTransform = Matrix4.compose(localMid, rotation, scale);

    // Create the pipe node using the computed local transform.
    final node = ARNode(
      type: NodeType.localGLTF2,
      uri: uri,
      transformation: localTransform,
    );

    if (await objectMgr.addNode(node, planeAnchor: midAnchor) != true) {
      await anchorMgr.removeAnchor(midAnchor);
      return null;
    }

    return _PipeSegment(anchor: midAnchor, node: node);
  }

  // Extract the plane normal (Y axis) from an anchor transform.
  Vector3 _planeNormal(Matrix4 transform) {
    final axisY = Vector3(
      transform.entry(0, 1),
      transform.entry(1, 1),
      transform.entry(2, 1),
    );
    if (axisY.length2 == 0) {
      return Vector3(0, 1, 0);
    }
    return axisY.normalized();
  }

  // <=====================Remove Anchors, Nodes and Pipes=====================>
  Future<void> _removeEverything() async {
    await _removeNodeList(_nodes);
    await _removeAnchors(_midAnchors);
    await _removeTapAnchors(List<ARPlaneAnchor>.from(_anchors));
    setState(() {});
  }

  Future<void> _removeNodeList(List<ARNode> nodes) async {
    final objectMgr = _objectManager;
    if (objectMgr == null) return;
    for (final node in List<ARNode>.from(nodes)) {
      await objectMgr.removeNode(node);
      nodes.remove(node);
    }
  }

  Future<void> _removeAnchors(List<ARPlaneAnchor> anchors) async {
    final anchorMgr = _anchorManager;
    if (anchorMgr == null) return;
    for (final anchor in List<ARPlaneAnchor>.from(anchors)) {
      await anchorMgr.removeAnchor(anchor);
      anchors.remove(anchor);
    }
  }

  Future<void> _removeTapAnchors(Iterable<ARPlaneAnchor> anchors) async {
    final anchorMgr = _anchorManager;
    if (anchorMgr == null) return;
    for (final anchor in anchors) {
      _removeDepthGuidesForAnchor(anchor);
      await anchorMgr.removeAnchor(anchor);
      _anchors.remove(anchor);
    }
  }
}
