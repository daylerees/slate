// A grid in a dock menu, above its items: More's apps and Downloads' files, four across, three
// rows and then it scrolls, with Slate's scrolling shades, thin scrollbar and smooth wheel.
// Dock.qml gives it its cells:
//   DockGrid { menu: appMenu; dock: win; model: …; delegate: Item { width: 88; height: 92 … } }
// While it's open, the menu's gridFlick is this, for the dock's test state (which reads its
// cells, shades and scrollbar).

import QtQuick

Flickable {
    id: grid
    required property var menu          // the menu it's in (the dock's appMenu)
    required property var dock          // the dock (Dock.qml)
    property alias model: cellsRepeater.model
    property alias delegate: cellsRepeater.delegate
    width: menu.menuWidth - 16
    height: Math.min(cellsGrid.height, 3 * 92)        // three rows; the rest scroll
    contentHeight: cellsGrid.height
    interactive: contentHeight > height
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    SmoothWheel { flick: grid }
    readonly property Item cells: cellsGrid
    readonly property Item topShade: shadeTop
    readonly property Item bottomShade: shadeBottom
    readonly property Item bar: scrollBar
    Component.onCompleted: menu.gridFlick = grid
    Component.onDestruction: if (menu.gridFlick === grid) menu.gridFlick = null
    // (over the cells only, the scrollbar beside them left clear)
    ScrollShade { id: shadeTop; z: 3; y: grid.contentY; width: cellsGrid.width; cornerRadius: grid.menu.gridCorner
                  height: 28; depth: grid.menu.gridShadeDepth; distance: grid.contentY }
    ScrollShade { id: shadeBottom; z: 3; atBottom: true; y: grid.contentY + grid.height - height; width: cellsGrid.width
                  height: 28; depth: grid.menu.gridShadeDepth; cornerRadius: grid.menu.gridCorner
                  distance: grid.contentHeight - grid.height - grid.contentY }
    ThinScrollbar { id: scrollBar; z: 3; flick: grid; color: grid.dock.textColor; x: grid.width - width; y: grid.contentY; height: grid.height }
    Grid {
        id: cellsGrid
        columns: 4
        Repeater { id: cellsRepeater }
    }
}
