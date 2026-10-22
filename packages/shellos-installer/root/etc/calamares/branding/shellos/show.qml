/* ShellOS installer slideshow: one calm slide, the spiral on dark. */
import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation

    Rectangle {
        anchors.fill: parent
        color: "#0B1416"
    }

    Slide {
        Image {
            id: logo
            source: "logo.png"
            width: 160; height: 160
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -40
        }
        Text {
            anchors.top: logo.bottom
            anchors.topMargin: 28
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            color: "#E6F4F2"
            font.pixelSize: 18
            text: "Installing ShellOS.<br/>" +
                  "<span style='color:#7FD8CF'>COSMIC · BORE + LAVD · Btrfs snapshots · Limine</span>"
        }
    }

    function onActivate() { }
    function onLeave() { }
}
