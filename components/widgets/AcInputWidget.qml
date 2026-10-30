/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
*/

import QtQuick
import QtQuick.Layouts
import Victron.VenusOS

AcWidget {
	id: root

	readonly property AcInputSystemInfo inputInfo: input?.inputInfo ?? null
	readonly property bool inputOperational: input && input.operational

	readonly property bool _showSideGauge: inputOperational && size >= VenusOS.OverviewWidget_Size_M

	// Grid input: show a 5 s moving average for the big total-power number instead of the
	// instantaneous value (the EM540 grid meter updates at ~6 Hz, making it bounce).
	// The average is published by the dbus-gridaverage service; the phase (L1/L2/L3) values
	// stay instantaneous. Falls back to the live power if the average service is unavailable.
	readonly property bool _isGridInput: inputInfo?.source === VenusOS.AcInputs_InputSource_Grid
	readonly property VeQuickItem _gridAvgPower: VeQuickItem {
		uid: root._isGridInput
			? BackendConnection.serviceUidFromName("com.victronenergy.gridaverage.cgwacs_ttyUSB3_mb1", 0) + "/Ac/Power"
			: ""
	}
	readonly property QtObject _gridAvgDataObject: QtObject {
		readonly property real power: root._gridAvgPower.valid ? root._gridAvgPower.value
				: (root.input ? root.input.power : NaN)
		readonly property real current: root.input ? root.input.current : NaN
	}

	rightPadding: _showSideGauge ? Theme.geometry_overviewPage_widget_sideGauge_margins
			: Theme.geometry_overviewPage_widget_content_horizontalMargin
	title: !!inputInfo ? Global.acInputs.sourceToText(inputInfo.source) : ""
	quantitySourceType: VenusOS.ElectricalQuantity_Source_AcInputOnly
	quantityDataObject: !inputOperational ? null
			: (_isGridInput && _gridAvgPower.valid) ? _gridAvgDataObject
			: input
	phaseModel: inputOperational && input.phases.count > 1 ? input.phases : null
	enabled: !!inputInfo

	contentItem: Item {
		implicitWidth: Theme.geometry_overviewPage_widget_leftWidgetWidth
		implicitHeight: contentLayout.implicitHeight

		AcWidgetContent {
			id: contentLayout

			width: parent.width - (sideGaugeLoader.active ? sideGaugeLoader.width + Theme.geometry_overviewPage_widget_sideGauge_margins : 0)
			height: parent.height
			widget: root
			iconSource: !!root.inputInfo ? Global.acInputs.sourceIcon(root.inputInfo.source) : ""
			stateText: root.inputOperational ? ""
					: root.inputInfo && root.inputInfo.source === VenusOS.AcInputs_InputSource_Generator ? CommonWords.stopped
					: CommonWords.disconnected
		}

		Loader {
			id: sideGaugeLoader

			anchors {
				top: parent.top
				bottom: parent.bottom
				right: parent.right
			}
			active: root._showSideGauge
			sourceComponent: ThreePhaseBarGauge {
				valueType: VenusOS.Gauges_ValueType_NeutralPercentage
				phaseModel: root.input.phases
				minimumValue: root.inputInfo?.minimumCurrent ?? NaN
				maximumValue: root.inputInfo?.maximumCurrent ?? NaN
				inputMode: true
				animationEnabled: root.animationEnabled
				inOverviewWidget: true
			}
		}
	}

	onClicked: {
		const inputServiceUid = BackendConnection.serviceUidFromName(root.inputInfo.serviceName, root.inputInfo.deviceInstance)
		if (root.inputInfo.serviceType === "acsystem") {
			Global.pageManager.pushPage("/pages/settings/devicelist/rs/PageRsSystem.qml",
					{ "bindPrefix": inputServiceUid })
		} else if (root.inputInfo.serviceType === "vebus") {
			Global.pageManager.pushPage( "/pages/vebusdevice/PageVeBus.qml", {
				"bindPrefix": inputServiceUid
			})
		} else if (root.inputInfo.serviceType === "genset") {
			Global.pageManager.pushPage( "/pages/settings/devicelist/PageGenset.qml", {
				"bindPrefix": inputServiceUid
			})
		} else {
			// Assume this is on a generic AC input
			Global.pageManager.pushPage("/pages/settings/devicelist/ac-in/PageAcIn.qml", {
				"bindPrefix": inputServiceUid
			})
		}
	}
}
