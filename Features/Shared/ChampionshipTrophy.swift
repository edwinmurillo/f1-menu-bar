import SwiftUI

struct ChampionshipTrophy: View {
    var projected = false
    var body: some View {
        Image(systemName: "trophy.fill")
            .foregroundStyle(Color(red: 0.85, green: 0.65, blue: 0.13))
            .help(projected ? "World championship secured with these projected results" : "World championship secured")
            .accessibilityLabel(projected ? "Projected world champion" : "World champion")
    }
}
