import SwiftUI

struct PaperBackground: View {
    @Environment(\.ledgerTheme) private var theme

    var body: some View {
        theme.paper.overlay {
            Canvas { context, size in
                for row in 0...Int(size.height / 105) {
                    for col in 0...Int(size.width / 108) {
                        let x = CGFloat(col) * 108 + (row.isMultiple(of: 2) ? 10 : 58)
                        let y = CGFloat(row) * 105 + 25
                        var paw = Path()
                        paw.addEllipse(in: CGRect(x: x, y: y + 13, width: 25, height: 21))
                        for (dx, dy) in [(-5.0, 4.0), (4.0, -5.0), (16.0, -5.0), (25.0, 4.0)] {
                            paw.addEllipse(in: CGRect(x: x + dx, y: y + dy, width: 9, height: 11))
                        }
                        context.fill(paw, with: .color(theme.primary.opacity(0.055)))
                    }
                }
            }
            .accessibilityHidden(true)
        }.ignoresSafeArea()
    }
}

struct PaperCard: ViewModifier {
    @Environment(\.ledgerTheme) private var theme
    var fill: Color?
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content.background(fill ?? theme.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(theme.ink, lineWidth: 1.5) }
    }
}
extension View {
    func paperCard(fill: Color? = nil, radius: CGFloat = 12) -> some View {
        modifier(PaperCard(fill: fill, radius: radius))
    }
}

struct PaperButtonStyle: ButtonStyle {
    @Environment(\.ledgerTheme) private var theme
    var fill: Color?
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .paperCard(fill: fill ?? theme.surface)
            .offset(y: configuration.isPressed ? 2 : 0)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct DashedRule: View {
    @Environment(\.ledgerTheme) private var theme

    var body: some View {
        Rectangle().fill(theme.ink.opacity(0.55)).frame(height: 1)
            .mask { HStack(spacing: 5) { ForEach(0..<80, id: \.self) { _ in Rectangle().frame(width: 5) } } }
            .accessibilityHidden(true)
    }
}

struct CategoryIllustration: View {
    @Environment(\.ledgerTheme) private var theme
    let name: String
    var size: CGFloat = 44
    var body: some View {
        let ink = theme.ink
        Canvas { context, dimensions in
            let scale = dimensions.width / 48
            context.scaleBy(x: scale, y: scale)
            func draw(_ path: Path, _ color: Color) {
                context.fill(path, with: .color(color))
                context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
            func line(_ points: [CGPoint]) {
                var p = Path(); p.addLines(points)
                context.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
            switch name {
            case "餐饮":
                var bowl = Path(); bowl.move(to: CGPoint(x: 8,y: 23)); bowl.addLine(to: CGPoint(x: 40,y: 23)); bowl.addQuadCurve(to: CGPoint(x: 33,y: 39), control: CGPoint(x: 39,y: 39)); bowl.addLine(to: CGPoint(x: 15,y: 39)); bowl.addQuadCurve(to: CGPoint(x: 8,y: 23), control: CGPoint(x: 9,y: 39)); bowl.closeSubpath(); draw(bowl, theme.artwork.yellow)
                draw(Path(ellipseIn: CGRect(x: 13,y: 11,width: 22,height: 15)), theme.surface)
                line([CGPoint(x: 19,y: 11),CGPoint(x: 18,y: 6),CGPoint(x: 22,y: 3)])
                line([CGPoint(x: 28,y: 11),CGPoint(x: 27,y: 7)])
                line([CGPoint(x: 17,y: 43),CGPoint(x: 31,y: 43)])
            case "购物":
                draw(Path(roundedRect: CGRect(x: 11,y: 17,width: 27,height: 26),cornerRadius: 3), theme.artwork.shopping)
                var handle = Path(); handle.addArc(center: CGPoint(x: 24.5,y: 17),radius: 8,startAngle: .degrees(180),endAngle: .degrees(0),clockwise: false); context.stroke(handle, with: .color(theme.ink), lineWidth: 2)
                line([CGPoint(x: 17,y: 19),CGPoint(x: 17,y: 23)]); line([CGPoint(x: 32,y: 19),CGPoint(x: 32,y: 23)])
            case "交通":
                draw(Path(roundedRect: CGRect(x: 9,y: 7,width: 30,height: 33),cornerRadius: 7), theme.artwork.transport)
                draw(Path(roundedRect: CGRect(x: 13,y: 12,width: 22,height: 14),cornerRadius: 3), theme.surface)
                draw(Path(ellipseIn: CGRect(x: 13,y: 31,width: 5,height: 5)), theme.artwork.yellow)
                draw(Path(ellipseIn: CGRect(x: 30,y: 31,width: 5,height: 5)), theme.artwork.yellow)
                line([CGPoint(x: 15,y: 41),CGPoint(x: 15,y: 45)]); line([CGPoint(x: 33,y: 41),CGPoint(x: 33,y: 45)])
            case "宠物":
                var ears = Path()
                ears.addLines([CGPoint(x: 10,y: 20),CGPoint(x: 8,y: 5),CGPoint(x: 20,y: 12),CGPoint(x: 29,y: 12),CGPoint(x: 40,y: 5),CGPoint(x: 38,y: 21)])
                ears.closeSubpath(); draw(ears, theme.artwork.yellow)
                draw(Path(ellipseIn: CGRect(x: 8,y: 12,width: 33,height: 27)), theme.artwork.yellow)
                draw(Path(ellipseIn: CGRect(x: 13,y: 35,width: 23,height: 9)), theme.artwork.petMuzzle)
                line([CGPoint(x: 18,y: 24),CGPoint(x: 18,y: 25)])
                line([CGPoint(x: 31,y: 24),CGPoint(x: 31,y: 25)])
                line([CGPoint(x: 23,y: 27),CGPoint(x: 25,y: 29),CGPoint(x: 27,y: 27)])
                line([CGPoint(x: 25,y: 29),CGPoint(x: 25,y: 32)])
                line([CGPoint(x: 8,y: 26),CGPoint(x: 13,y: 27)])
                line([CGPoint(x: 36,y: 27),CGPoint(x: 41,y: 26)])
            case "住房":
                draw(Path(roundedRect: CGRect(x: 12,y: 21,width: 25,height: 23),cornerRadius: 1), theme.surface)
                var roof = Path(); roof.addLines([CGPoint(x: 5,y: 23),CGPoint(x: 24,y: 5),CGPoint(x: 43,y: 23)]); roof.closeSubpath()
                draw(roof, theme.artwork.housingRoof)
                draw(Path(CGRect(x: 22,y: 29,width: 8,height: 15)), theme.artwork.housingDoor)
                draw(Path(CGRect(x: 15,y: 28,width: 5,height: 7)), theme.artwork.housingWindow)
                line([CGPoint(x: 9,y: 44),CGPoint(x: 40,y: 44)])
            case "零食":
                var cake = Path(); cake.addLines([CGPoint(x: 12,y: 24),CGPoint(x: 36,y: 24),CGPoint(x: 32,y: 43),CGPoint(x: 16,y: 43)]); cake.closeSubpath()
                draw(cake, theme.artwork.snackCake)
                var icing = Path(); icing.move(to: CGPoint(x: 10,y: 24))
                icing.addCurve(to: CGPoint(x: 15,y: 15),control1: CGPoint(x: 5,y: 19),control2: CGPoint(x: 9,y: 13))
                icing.addCurve(to: CGPoint(x: 24,y: 9),control1: CGPoint(x: 14,y: 7),control2: CGPoint(x: 20,y: 7))
                icing.addCurve(to: CGPoint(x: 34,y: 15),control1: CGPoint(x: 31,y: 7),control2: CGPoint(x: 36,y: 9))
                icing.addCurve(to: CGPoint(x: 38,y: 24),control1: CGPoint(x: 42,y: 13),control2: CGPoint(x: 45,y: 21))
                icing.addQuadCurve(to: CGPoint(x: 10,y: 24),control: CGPoint(x: 24,y: 30)); icing.closeSubpath(); draw(icing, theme.artwork.snackIcing)
                draw(Path(ellipseIn: CGRect(x: 21,y: 5,width: 7,height: 7)), theme.artwork.pink)
                line([CGPoint(x: 19,y: 30),CGPoint(x: 21,y: 39)])
                line([CGPoint(x: 29,y: 30),CGPoint(x: 27,y: 39)])
            case "旅行":
                var plane = Path(); plane.addLines([
                    CGPoint(x: 5,y: 13),CGPoint(x: 22,y: 16),CGPoint(x: 34,y: 5),CGPoint(x: 41,y: 5),CGPoint(x: 41,y: 12),
                    CGPoint(x: 30,y: 25),CGPoint(x: 34,y: 43),CGPoint(x: 27,y: 39),CGPoint(x: 22,y: 30),
                    CGPoint(x: 15,y: 37),CGPoint(x: 15,y: 43),CGPoint(x: 10,y: 39),CGPoint(x: 5,y: 34),
                    CGPoint(x: 11,y: 33),CGPoint(x: 18,y: 25),CGPoint(x: 9,y: 20)])
                plane.closeSubpath(); draw(plane, theme.artwork.travel)
                line([CGPoint(x: 24,y: 21),CGPoint(x: 34,y: 12)])
            case "通讯":
                var phone = Path(); phone.move(to: CGPoint(x: 34,y: 5))
                phone.addCurve(to: CGPoint(x: 29,y: 14),control1: CGPoint(x: 27,y: 5),control2: CGPoint(x: 26,y: 8))
                phone.addLine(to: CGPoint(x: 32,y: 20))
                phone.addCurve(to: CGPoint(x: 21,y: 32),control1: CGPoint(x: 30,y: 27),control2: CGPoint(x: 26,y: 31))
                phone.addLine(to: CGPoint(x: 15,y: 28))
                phone.addCurve(to: CGPoint(x: 6,y: 32),control1: CGPoint(x: 11,y: 26),control2: CGPoint(x: 7,y: 28))
                phone.addCurve(to: CGPoint(x: 16,y: 43),control1: CGPoint(x: 4,y: 38),control2: CGPoint(x: 10,y: 43))
                phone.addCurve(to: CGPoint(x: 42,y: 15),control1: CGPoint(x: 28,y: 43),control2: CGPoint(x: 42,y: 26))
                phone.addCurve(to: CGPoint(x: 34,y: 5),control1: CGPoint(x: 42,y: 10),control2: CGPoint(x: 39,y: 5)); phone.closeSubpath()
                draw(phone, theme.artwork.communication)
                for radius in [10.0,16.0] {
                    var signal = Path(); signal.addArc(center: CGPoint(x: 22,y: 22),radius: radius,startAngle: .degrees(185),endAngle: .degrees(265),clockwise: false)
                    context.stroke(signal,with: .color(theme.ink),style: StrokeStyle(lineWidth: 1.8,lineCap: .round))
                }
            case "医疗":
                draw(Path(roundedRect: CGRect(x: 15,y: 5,width: 18,height: 11),cornerRadius: 3), theme.surface)
                draw(Path(roundedRect: CGRect(x: 7,y: 13,width: 34,height: 30),cornerRadius: 6), theme.artwork.medical)
                var cross = Path(); cross.addLines([CGPoint(x: 21,y: 20),CGPoint(x: 27,y: 20),CGPoint(x: 27,y: 26),CGPoint(x: 33,y: 26),CGPoint(x: 33,y: 32),CGPoint(x: 27,y: 32),CGPoint(x: 27,y: 38),CGPoint(x: 21,y: 38),CGPoint(x: 21,y: 32),CGPoint(x: 15,y: 32),CGPoint(x: 15,y: 26),CGPoint(x: 21,y: 26)])
                cross.closeSubpath(); draw(cross, theme.surface)
            case "Pos":
                var ticket = Path(); ticket.move(to: CGPoint(x: 7,y: 10)); ticket.addLine(to: CGPoint(x: 41,y: 10)); ticket.addLine(to: CGPoint(x: 41,y: 19))
                ticket.addQuadCurve(to: CGPoint(x: 41,y: 29),control: CGPoint(x: 32,y: 24))
                ticket.addLine(to: CGPoint(x: 41,y: 39)); ticket.addLine(to: CGPoint(x: 7,y: 39)); ticket.addLine(to: CGPoint(x: 7,y: 29))
                ticket.addQuadCurve(to: CGPoint(x: 7,y: 19),control: CGPoint(x: 16,y: 24)); ticket.closeSubpath()
                draw(ticket, theme.artwork.pos)
                context.draw(Text("¥").font(.system(size: 23,weight: .medium,design: .rounded)).foregroundStyle(theme.ink),at: CGPoint(x: 24,y: 25))
            case "其它", "其他支出":
                draw(Path(roundedRect: CGRect(x: 8,y: 7,width: 32,height: 34),cornerRadius: 5), theme.artwork.other)
                for x in [16.0,24.0,32.0] { context.fill(Path(ellipseIn: CGRect(x: x - 1.5,y: 22,width: 3,height: 3)),with: .color(theme.ink)) }
            case "礼金":
                var bag = Path(); bag.move(to: CGPoint(x: 17,y: 17)); bag.addLine(to: CGPoint(x: 31,y: 17))
                bag.addCurve(to: CGPoint(x: 41,y: 36),control1: CGPoint(x: 35,y: 23),control2: CGPoint(x: 42,y: 29))
                bag.addQuadCurve(to: CGPoint(x: 7,y: 36),control: CGPoint(x: 24,y: 47))
                bag.addCurve(to: CGPoint(x: 17,y: 17),control1: CGPoint(x: 6,y: 30),control2: CGPoint(x: 13,y: 23)); bag.closeSubpath(); draw(bag, theme.artwork.pink)
                var heart = Path(); heart.move(to: CGPoint(x: 24,y: 17)); heart.addCurve(to: CGPoint(x: 14,y: 7),control1: CGPoint(x: 17,y: 14),control2: CGPoint(x: 10,y: 8))
                heart.addQuadCurve(to: CGPoint(x: 24,y: 6),control: CGPoint(x: 17,y: 0)); heart.addQuadCurve(to: CGPoint(x: 34,y: 7),control: CGPoint(x: 33,y: 0))
                heart.addQuadCurve(to: CGPoint(x: 24,y: 17),control: CGPoint(x: 36,y: 12)); heart.closeSubpath(); draw(heart, theme.artwork.pink)
                draw(Path(ellipseIn: CGRect(x: 16,y: 25,width: 17,height: 12)), theme.surface)
                line([CGPoint(x: 20,y: 30),CGPoint(x: 29,y: 30)])
            case "运动":
                var shoe = Path(); shoe.move(to: CGPoint(x: 8,y: 29)); shoe.addLine(to: CGPoint(x: 9,y: 17)); shoe.addLine(to: CGPoint(x: 18,y: 20))
                shoe.addLine(to: CGPoint(x: 23,y: 14)); shoe.addQuadCurve(to: CGPoint(x: 34,y: 25),control: CGPoint(x: 25,y: 25))
                shoe.addQuadCurve(to: CGPoint(x: 42,y: 31),control: CGPoint(x: 43,y: 23)); shoe.addLine(to: CGPoint(x: 42,y: 38)); shoe.addLine(to: CGPoint(x: 7,y: 38)); shoe.closeSubpath()
                draw(shoe, theme.artwork.sport)
                line([CGPoint(x: 7,y: 33),CGPoint(x: 42,y: 33)])
                line([CGPoint(x: 21,y: 22),CGPoint(x: 26,y: 19)])
                line([CGPoint(x: 26,y: 26),CGPoint(x: 31,y: 23)])
                var motion = Path(); motion.move(to: CGPoint(x: 8,y: 9)); motion.addQuadCurve(to: CGPoint(x: 21,y: 15),control: CGPoint(x: 19,y: 7))
                motion.move(to: CGPoint(x: 8,y: 4)); motion.addQuadCurve(to: CGPoint(x: 25,y: 12),control: CGPoint(x: 21,y: 2))
                context.stroke(motion,with: .color(theme.ink),style: StrokeStyle(lineWidth: 1.6,lineCap: .round))
            case "日用":
                draw(Path(roundedRect: CGRect(x: 9,y: 13,width: 24,height: 29),cornerRadius: 5), theme.artwork.daily)
                draw(Path(ellipseIn: CGRect(x: 9,y: 8,width: 24,height: 12)), theme.artwork.dailyTop)
                draw(Path(ellipseIn: CGRect(x: 17,y: 11,width: 8,height: 5)), theme.surface)
                var paper = Path(); paper.addLines([CGPoint(x: 30,y: 16),CGPoint(x: 39,y: 18),CGPoint(x: 39,y: 43),CGPoint(x: 30,y: 40)]); paper.closeSubpath(); draw(paper, theme.surface)
            case "工资", "奖金", "其他收入":
                draw(Path(roundedRect: CGRect(x: 6,y: 12,width: 36,height: 27),cornerRadius: 4), theme.artwork.income)
                draw(Path(ellipseIn: CGRect(x: 16,y: 16,width: 16,height: 19)), theme.artwork.yellow)
                context.draw(Text("¥").font(.system(size: 14,weight: .bold)).foregroundStyle(theme.ink), at: CGPoint(x: 24,y: 25))
                line([CGPoint(x: 10,y: 17),CGPoint(x: 10,y: 22)]); line([CGPoint(x: 38,y: 29),CGPoint(x: 38,y: 34)])
            default:
                draw(Path(roundedRect: CGRect(x: 8,y: 14,width: 32,height: 28),cornerRadius: 5), theme.artwork.fallback)
                draw(Path(roundedRect: CGRect(x: 16,y: 7,width: 16,height: 9),cornerRadius: 3), theme.surface)
                line([CGPoint(x: 8,y: 25),CGPoint(x: 40,y: 25)])
                draw(Path(roundedRect: CGRect(x: 21,y: 22,width: 6,height: 8),cornerRadius: 1), theme.artwork.yellow)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct CategoryBadge: View {
    @Environment(\.ledgerTheme) private var theme
    let name: String
    var selected = false
    var size: CGFloat = 54
    var body: some View {
        CategoryIllustration(name: name, size: size * 0.66)
            .frame(width: size, height: size)
            .background(selected ? theme.primarySoft : theme.surface, in: Circle())
            .overlay { Circle().stroke(selected ? theme.primary : theme.ink, lineWidth: selected ? 2.5 : 1.4) }
    }
}
