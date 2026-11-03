/*
** Copyright (C) 2026 ZeRo-244
** Custom connector for AC-coupled PV on the inverter's AC-OUTPUT bus.
**
** The stock WidgetConnector can only draw a symmetric Z (its riser is locked to the
** midpoint of the two widgets), so it cannot draw the asymmetric L that routes a PV
** line from the bottom-left Solar tile, through the inverter<->battery gap, and up to
** the inverter<->AC Loads (AC-out) node without the riser landing behind the Battery.
**
** This component draws that route explicitly as one rounded polyline with quadratic
** (handedness-free) corners, and reuses the stock electron machinery for the flow
** animation so it matches the other connectors. Route (all in root coords):
**   P0 Solar-right -> P1 turn up -> P2 turn right (gap centre) -> P3 turn up
**   (centre of inverter<->AC Loads space) -> tap the AC-out node.
*/
import QtQuick
import QtQuick.Shapes
import Victron.VenusOS

Item {
	id: root

	anchors.fill: parent   // fill the page so the Shape's absolute-coord drawing isn't clipped

	// Geometry inputs (all OverviewWidget instances in the page's root coord system).
	property var solarWidget
	property var inverterWidget
	property var batteryWidget
	property var acLoadsWidget

	property bool active: false          // show the route (PV is on the AC-out bus)
	property bool flowing: false         // animate electrons (PV power over threshold)
	property bool animationEnabled: true
	required property var frameAnimation

	readonly property real _aw: Theme.geometry_overviewPage_connector_anchor_width
	readonly property real _spacing: Theme.geometry_overviewPage_widget_spacing
	// Target corner radius; capped below so it never exceeds a leg.
	readonly property real _baseRadius: 2.2 * Theme.geometry_overviewPage_connector_anchor_width

	// --- Route points -------------------------------------------------------------
	readonly property real _p0x: solarWidget.x + solarWidget.width + _aw
	readonly property real _p0y: solarWidget.compactY + solarWidget.compactHeight / 2
	readonly property real _invRight: inverterWidget.x + inverterWidget.width
	readonly property real _invBottom: inverterWidget.compactY + inverterWidget.compactHeight
	readonly property real _ty: inverterWidget.compactY + inverterWidget.compactHeight / 2   // AC-out node Y (inverter centre)
	readonly property real _gy: (_invBottom + batteryWidget.compactY) / 2                     // gap centre Y
	readonly property real _lx: inverterWidget.x - _spacing                                   // riser X, clear corridor left of battery
	// AC Loads<->EVCS connector riser X (acLoads.Left minus a quarter of the inverter<->rightcol gap).
	readonly property real _acLoadsEvcsX: acLoadsWidget.x - _aw - (acLoadsWidget.x - _invRight) / 4
	readonly property real _cx: (_invRight + _acLoadsEvcsX) / 2                               // vertical X, centred in that space

	readonly property real _r: Math.max(2, Math.min(_baseRadius,
			_lx - _p0x, (_p0y - _gy) / 2, (_cx - _lx) / 2, _gy - _ty))

	// Approx path length for electron spacing/speed (straight-leg sum).
	readonly property real _pathLength: (_lx - _p0x) + (_p0y - _gy) + (_cx - _lx) + (_gy - _ty)

	visible: active && solarWidget.visible && inverterWidget.visible

	onVisibleChanged: Qt.callLater(_resetElectrons)
	on_PathLengthChanged: Qt.callLater(_resetElectrons)
	on_AnimatedChanged: Qt.callLater(_resetElectrons)

	readonly property bool _animated: visible && flowing && animationEnabled

	function _resetElectrons() {
		const dist = Math.max(Theme.geometry_overviewPage_connector_electron_interval, _pathLength)
		const modelCount = animationEnabled
				? Math.floor(dist / Theme.geometry_overviewPage_connector_electron_interval)
				: 1
		if (electronRepeater.count !== modelCount) {
			electronRepeater.model = modelCount
			const fadeDistance = 2 * Theme.geometry_overviewPage_connector_anchor_width
			pathUpdater.fadeOutThreshold = dist > 0 ? (dist - fadeDistance) / dist : 1
		}
		if (_animated) {
			pathUpdater.duration = dist / Theme.geometry_overviewPage_connector_electron_velocity * 1000
		}
		if (frameAnimation.paused || !_animated) {
			pathUpdater.update()
		}
	}

	// Rounded polyline, shared by the drawn line and the electron path.
	property list<QtObject> _pathEls: [
		PathLine { x: root._lx - root._r; y: root._p0y },                         // P0 -> approach P1
		PathQuad { controlX: root._lx; controlY: root._p0y; x: root._lx; y: root._p0y - root._r },  // round P1 (right->up)
		PathLine { x: root._lx; y: root._gy + root._r },                          // up -> approach P2
		PathQuad { controlX: root._lx; controlY: root._gy; x: root._lx + root._r; y: root._gy },    // round P2 (up->right)
		PathLine { x: root._cx - root._r; y: root._gy },                          // across -> approach P3
		PathQuad { controlX: root._cx; controlY: root._gy; x: root._cx; y: root._gy - root._r },    // round P3 (right->up)
		PathLine { x: root._cx; y: root._ty }                                     // up -> tap AC-out node
	]

	Shape {
		anchors.fill: parent
		ShapePath {
			strokeWidth: Theme.geometry_overviewPage_connector_line_width
			strokeColor: Theme.color_overviewPage_widget_border
			fillColor: "transparent"
			startX: root._p0x
			startY: root._p0y
			pathElements: root._pathEls
		}

		Repeater {
			id: electronRepeater
			delegate: Image {
				opacity: 0.0
				source: root.animationEnabled ? "qrc:/images/electron.svg" : "qrc:/images/electron_arrow.svg"
				visible: root._animated
				rotation: root.animationEnabled ? 0.0 : pathUpdater.angleForArrow(pathUpdater.progress, pathUpdater.startToEnd)
				Behavior on opacity {
					enabled: root._animated
					OpacityAnimator { duration: Theme.animation_overviewPage_connector_fade_duration }
				}
				Component.onCompleted: pathUpdater.add(this)
				Component.onDestruction: pathUpdater.remove(this)
			}
		}
	}

	WidgetConnectorPathUpdater {
		id: pathUpdater
		property real duration
		property real normalizedElapsed: 1000 * root.frameAnimation.animationElapsed / Math.max(1, pathUpdater.duration)
		readonly property real loopedElapsed: normalizedElapsed - Math.trunc(normalizedElapsed)
		readonly property bool startToEnd: true
		progress: root.animationEnabled ? loopedElapsed : 0.515
		animationMode: root._animated ? VenusOS.WidgetConnector_AnimationMode_StartToEnd
									  : VenusOS.WidgetConnector_AnimationMode_NotAnimated
		path: Path {
			startX: root._p0x
			startY: root._p0y
			pathElements: root._pathEls
		}
	}
}
