import CoreGraphics

struct ViewStyle {
    var flex: FlexStyle = FlexStyle()

    var backgroundColor: CGColor?
    var borderRadius: Double = 0
    var opacity: Double = 1
    var borderWidth: Double = 0
    var borderColor: CGColor?

    var fontSize: Double = 14
    var fontWeight: String = "regular"
    var fontFamily: String?
    var color: CGColor?
    var textAlign: String = "left"
    var numberOfLines: Int = 0
    var lineHeight: Double = 0
}
