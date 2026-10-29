import SwiftUI

enum SessionHomeCopy {
    static func message(at date: Date, calendar: Calendar = .current) -> (title: String, detail: String) {
        let hour = calendar.component(.hour, from: date)
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let messages: [(String, String)]
        switch hour {
        case 6..<12:
            messages = [
                ("A fresh branch. A fresh start.", L("오늘의 첫 작업을 시작해 볼까요?", "Ready for your first task today?")),
                ("Make something good today.", L("작은 변경도 앞으로 나아가는 한 걸음입니다.", "Small changes move things forward.")),
                ("One prompt at a time.", L("아침의 좋은 아이디어를 이어가세요.", "Give that morning idea a place to grow."))
            ]
        case 12..<18:
            messages = [
                ("A little space.\nFor your next big thing.", L("익숙한 CLI, 당신의 설정 그대로.", "The CLIs you know, with your own settings.")),
                ("Keep the good parts moving.", L("이 프로젝트에서 다음 작업을 이어가세요.", "Pick up the next task in this project.")),
                ("Build, pause, iterate.", L("필요한 에이전트를 바로 시작하세요.", "Start the agent you need."))
            ]
        case 18..<23:
            messages = [
                ("One last commit?", L("유명한 마지막 한 번. 그래도 시작해 볼까요?", "Famous last words. Ready when you are.")),
                ("Ship the small win.", L("오늘의 진전을 이 프로젝트에 남기세요.", "Leave a little progress in this project.")),
                ("The good idea can wait.\nOr not.", L("원하는 속도로 이어가세요.", "Keep going at your own pace."))
            ]
        default:
            messages = [
                ("Quiet screen. Loud ideas.", L("늦은 시간의 작은 작업 공간.", "A little workspace for late ideas.")),
                ("Tomorrow is a feature.", L("지금은 가볍게, 이어서 내일도 좋아요.", "A little now, or more tomorrow.")),
                ("The cursor can rest, too.", L("필요할 때 다시 이어가세요.", "It'll be here when you're ready."))
            ]
        }
        return messages[day % messages.count]
    }
}

struct ProjectActivityHeatmap: View {
    let activity: ProjectActivity
    let path: String
    let now: Date
    let importing: Bool
    let onImport: () -> Void

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }
    private var firstDay: Date {
        let today = calendar.startOfDay(for: now)
        let offset = (calendar.component(.weekday, from: today) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
        return calendar.date(byAdding: .weekOfYear, value: -11, to: monday) ?? monday
    }
    private var total: Int {
        (0..<ProjectActivity.daysShown).reduce(0) { sum, index in
            guard let day = calendar.date(byAdding: .day, value: index, to: firstDay), day <= now else { return sum }
            return sum + activity.count(in: path, on: day, calendar: calendar)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("이 프로젝트의 발자국", "This project's activity"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text(L("12주", "12 weeks")).font(.caption).foregroundStyle(Palette.muted)
                Button(action: onImport) {
                    Image(systemName: importing ? "hourglass" : "arrow.down.to.line")
                }
                .buttonStyle(.plain)
                .disabled(importing)
                .help(L("이 프로젝트의 과거 로컬 대화 가져오기", "Import past local conversations for this project"))
                .accessibilityLabel(L("과거 대화 가져오기", "Import past conversations"))
            }
            HStack(spacing: 4) {
                ForEach(0..<12, id: \.self) { week in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { weekday in
                            cell(dayOffset: week * 7 + weekday)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
            if importing {
                Text(L("로컬 대화를 확인하는 중…", "Checking local conversations…"))
                    .font(.caption).foregroundStyle(Palette.muted)
            } else if total == 0 {
                Button(L("과거 대화 가져오기", "Import past conversations"), action: onImport)
                    .font(.caption.weight(.medium)).foregroundStyle(Palette.mint).buttonStyle(.plain)
            } else {
                Text(L("최근 12주 · 응답 \(total)회", "Last 12 weeks · \(total) replies"))
                    .font(.caption).foregroundStyle(Palette.muted)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity)
        .background(Palette.surface).clipShape(.rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("이 프로젝트의 최근 12주 에이전트 응답 \(total)회", "\(total) agent replies in this project over 12 weeks"))
    }
    private func cell(dayOffset: Int) -> some View {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: firstDay) ?? now
        let count = activity.count(in: path, on: day, calendar: calendar)
        let future = calendar.startOfDay(for: day) > calendar.startOfDay(for: now)
        return RoundedRectangle(cornerRadius: 2)
            .fill(future ? Color.clear : count == 0 ? Color.white.opacity(0.09) : Palette.mint.opacity(count == 1 ? 0.35 : count < 4 ? 0.65 : 1))
            .frame(width: 18, height: 18)
            .help(future ? "" : L("\(day.formatted(date: .abbreviated, time: .omitted)) · 응답 \(count)회", "\(day.formatted(date: .abbreviated, time: .omitted)) · \(count) replies"))
    }
}
