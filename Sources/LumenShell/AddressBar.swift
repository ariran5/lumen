import SwiftUI

struct AddressBar: View {
    @Bindable var tab: TabModel
    @FocusState private var isFocused: Bool

    private var leadingIcon: String {
        if tab.isLoading { return "ellipsis" }
        if tab.currentURL?.scheme == "https" { return "lock.fill" }
        if tab.currentURL != nil { return "globe" }
        return "magnifyingglass"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: leadingIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            TextField("Search or enter address", text: $tab.addressInput)
                .textFieldStyle(.plain)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($isFocused)
                .onSubmit {
                    tab.commit()
                    isFocused = false
                }

            if !tab.addressInput.isEmpty, isFocused {
                Button {
                    tab.addressInput = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}
