pragma Singleton

import QtQuick
import QtQuick.Shapes
import Quickshell

/**
 * ShapeCornerHelper — corner-arc math for the seamless connected-corner
 * background system (ported from noctalia; pure QtQuick.Shapes, no external
 * deps). Used to draw the bar/panels as one connected surface where concave
 * (outer/inverted) corners join them to the screen edges.
 *
 * 4-state per-corner system:
 *   -1  no radius (flat/square corner)
 *    0  normal (inner curve — a regular rounded corner)
 *    1  horizontal inversion (outer/concave curve on the X-axis)
 *    2  vertical inversion   (outer/concave curve on the Y-axis)
 *
 * Technique: PathArc direction (Clockwise vs Counterclockwise) plus per-axis
 * multipliers produce both inner and outer corner curves.
 */
Singleton {
    id: root

    // X-axis multiplier for a corner state (state 1 flips X).
    function getMultX(cornerState) {
        return cornerState === 1 ? -1 : 1;
    }

    // Y-axis multiplier for a corner state (state 2 flips Y).
    function getMultY(cornerState) {
        return cornerState === 2 ? -1 : 1;
    }

    // Arc direction from multipliers: XOR of the two sign flips selects an
    // outer (counter-clockwise) curve for inverted corners.
    function getArcDirection(multX, multY) {
        return ((multX < 0) !== (multY < 0)) ? PathArc.Counterclockwise : PathArc.Clockwise;
    }

    function getArcDirectionFromState(cornerState) {
        const multX = getMultX(cornerState);
        const multY = getMultY(cornerState);
        return getArcDirection(multX, multY);
    }

    // Clamp the radius when a dimension is too small, to avoid artifacts.
    function getFlattenedRadius(dimension, requestedRadius) {
        if (dimension < requestedRadius * 2) {
            return dimension / 2;
        }
        return requestedRadius;
    }

    function shouldFlatten(width, height, radius) {
        return width < radius * 2 || height < radius * 2;
    }
}
