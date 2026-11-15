import SwiftUI
import ReplayKit

struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let v = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
        v.preferredExtension = Shared.extensionBundleID
        v.showsMicrophoneButton = false
        return v
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var pip = PiPManager()
    @State private var st = Settings.load()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Gemini")) {
                    SecureField("API key (aistudio.google.com/apikey)", text: $st.apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Model", text: $st.model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Model du phong (cach nhau dau phay)", text: $st.fallbacks)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Ten phim / game (tuy chon)", text: $st.title)
                }

                Section(header: Text("Vung phu de (ti le man hinh)"),
                        footer: Text("Tinh theo man hinh dung chieu dang xem. Chinh sao cho khung chi bao tron dong phu de.")) {
                    sliderRow("Cach le tren", $st.y)
                    sliderRow("Chieu cao", $st.h)
                    sliderRow("Cach le trai", $st.x)
                    sliderRow("Chieu rong", $st.w)
                }

                Section(header: Text("Cach dung")) {
                    Button("1. Bat cua so chu Viet (PiP)") { pip.start() }
                    Button("Tat cua so chu Viet") { pip.stop() }
                    HStack {
                        Text("2. Bam nut ben canh de ghi man hinh")
                        Spacer()
                        BroadcastPicker().frame(width: 56, height: 56)
                    }
                    Text("Trang thai: \(pip.status)").font(.footnote).foregroundColor(.secondary)
                }

                Section(header: Text("Xem truoc")) {
                    PiPHostView(layer: pip.displayLayer)
                        .aspectRatio(4.0, contentMode: .fit)
                        .cornerRadius(8)
                    if !pip.lastText.isEmpty { Text(pip.lastText).font(.footnote) }
                }
            }
            .navigationTitle("Dich phu de")
            .onChange(of: st) { newValue in newValue.save() }
        }
        .navigationViewStyle(.stack)
    }

    private func sliderRow(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(Int(value.wrappedValue * 100))%").font(.footnote)
            Slider(value: value, in: 0...1)
        }
    }
}
