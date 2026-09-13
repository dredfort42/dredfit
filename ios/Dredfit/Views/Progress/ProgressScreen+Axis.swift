//
//  The date axis of the level chart: which dates it asks for, and how each
//  label is anchored. Its own file because both rules are asserted by
//  ProgressChartAxisTests, and because the second one is a Swift Charts
//  layout fact that only a render can settle.
//

import Charts
import SwiftUI

extension ProgressScreen {

    /// Dates can coincide (several workouts in one span), so duplicates
    /// collapse.
    func xAxisDates(_ points: [StepPoint]) -> [Date] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        let mid = points[points.count / 2].date
        var dates = [first]
        if mid > first && mid < last { dates.append(mid) }
        if last > first { dates.append(last) }
        return dates
    }

    /// Swift Charts anchors an x-axis label at its own date and grows it to
    /// the RIGHT, and a label that then does not fit is DROPPED — it is
    /// neither clipped nor nudged inward. The last date sits on the plot's
    /// right edge, so its label ran into the trailing y-axis column and past
    /// the chart's edge, and vanished: three labels asked for, two drawn, and
    /// the axis ending weeks before the line did (found on all seven App
    /// Store frames of this screen, 2.1.0). Anchoring only the last label by
    /// its trailing edge grows it leftwards instead, clear of the digits, and
    /// leaves the two labels that already fitted exactly where they were.
    ///
    /// Measured, not assumed: `collisionResolution: .disabled` and
    /// `.chartXScale(range: .plotDimension(endPadding:))` both still drop it,
    /// and `AxisMarkPreset.aligned` draws it on top of the y-axis digits.
    ///
    /// Index and count rather than the `AxisValue` they come from: that type
    /// has no public initialiser, so a rule taking one could not be asserted.
    static func xLabelAnchor(index: Int, count: Int) -> UnitPoint? {
        index == count - 1 ? .topTrailing : nil
    }
}
