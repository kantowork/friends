import Foundation
import SwiftUI

// MARK: - Type-Safe Localization Layer (L10n)
// AGENTS.md 命名規約準拠: 英語ドット記法キー (例: `auth.login.title`) を安全にラップします。

public enum L10n {
    
    // MARK: - Common
    public enum Common {
        public static var ok: String { tr("common.ok") }
        public static var cancel: String { tr("common.cancel") }
        public static var close: String { tr("common.close") }
        public static var copy: String { tr("common.copy") }
        public static var copied: String { tr("common.copied") }
        public static var share: String { tr("common.share") }
        public static var save: String { tr("common.save") }
        public static var delete: String { tr("common.delete") }
        public static var confirm: String { tr("common.confirm") }
        public static var error: String { tr("common.error") }
        public static var loading: String { tr("common.loading") }
        public static var success: String { tr("common.success") }
    }
    
    // MARK: - Auth & Login
    public enum Auth {
        public static var title: String { tr("auth.login.title") }
        public static var subtitle: String { tr("auth.login.subtitle") }
        public static var guestBtn: String { tr("auth.login.guest_btn") }
        public static var emailBtn: String { tr("auth.login.email_btn") }
        public static var recoveryBtn: String { tr("auth.login.recovery_btn") }
        public static var resetDeviceBtn: String { tr("auth.login.reset_device_btn") }
        public static var resetDeviceConfirmTitle: String { tr("auth.login.reset_device_confirm_title") }
        public static var resetDeviceConfirmMsg: String { tr("auth.login.reset_device_confirm_msg") }
        public static var tenantChange: String { tr("auth.login.tenant_change") }
        public static var displayNamePlaceholder: String { tr("auth.login.display_name_placeholder") }
    }
    
    // MARK: - Tenant Selection
    public enum Tenant {
        public static var selectionTitle: String { tr("tenant.selection.title") }
        public static var header: String { tr("tenant.selection.header") }
        public static var subtitle: String { tr("tenant.selection.subtitle") }
        public static var tabQR: String { tr("tenant.tab.qr") }
        public static var tabURL: String { tr("tenant.tab.url") }
        public static var tabCustom: String { tr("tenant.tab.custom") }
        public static var verifying: String { tr("tenant.verify.verifying") }
        public static var confirmBtn: String { tr("tenant.verify.confirm_btn") }
        public static var defaultBadge: String { tr("tenant.default_badge") }
        public static var inputLabel: String { tr("tenant.input.label") }
        public static var inputTemplate: String { tr("tenant.input.template") }
        public static var urlLabel: String { tr("tenant.input.url_label") }
        public static var verifyBtn: String { tr("tenant.verify.btn") }
        public static var cameraSimulatorNote: String { tr("tenant.camera.simulator_note") }
        public static var cameraSimulatorBtn: String { tr("tenant.camera.simulator_btn") }
    }
    
    // MARK: - Tabs
    public enum Tab {
        public static var home: String { tr("tab.home") }
        public static var friends: String { tr("tab.friends") }
        public static var groups: String { tr("tab.groups") }
    }
    
    // MARK: - Groups
    public enum Group {
        public static var listTitle: String { tr("group.list.title") }
        public static var listEmpty: String { tr("group.list.empty") }
        public static var createTitle: String { tr("group.create.title") }
        public static var nameLabel: String { tr("group.create.name_label") }
        public static var namePlaceholder: String { tr("group.create.name_placeholder") }
        public static func selectMembers(_ count: Int) -> String {
            String(format: tr("group.create.select_members"), count)
        }
        public static var submitBtn: String { tr("group.create.submit_btn") }
        public static var noFriends: String { tr("group.create.no_friends") }
        public static var detailTitle: String { tr("group.detail.title") }
        public static func membersSection(_ count: Int) -> String {
            String(format: tr("group.detail.members_section"), count)
        }
    }
    
    // MARK: - Chats
    public enum Chat {
        public static var listTitle: String { tr("chat.list.title") }
        public static var listEmpty: String { tr("chat.list.empty") }
        public static var inputPlaceholder: String { tr("chat.detail.input_placeholder") }
        public static var send: String { tr("chat.detail.send") }
        public static var readStatus: String { tr("chat.read.status") }
        public static func readCount(_ count: Int) -> String {
            String(format: tr("chat.read.count"), count)
        }
    }
    
    // MARK: - Reactions
    public enum Reaction {
        public static var detailsTitle: String { tr("chat.reaction.details_title") }
        public static var allTab: String { tr("chat.reaction.tab_all") }
        public static var emptyList: String { tr("chat.reaction.empty_list") }
        public static var thumbsUp: String { tr("chat.reaction.thumbs_up") }
        public static var heart: String { tr("chat.reaction.heart") }
        public static var ok: String { tr("chat.reaction.ok") }
        public static var smile: String { tr("chat.reaction.smile") }
        public static var surprised: String { tr("chat.reaction.surprised") }
        public static var sad: String { tr("chat.reaction.sad") }
        public static var thinking: String { tr("chat.reaction.thinking") }
        public static var you: String { tr("chat.reaction.you") }
    }
    
    // MARK: - Friends
    public enum Friend {
        public static var listTitle: String { tr("friend.list.title") }
        public static var addBtn: String { tr("friend.list.add_btn") }
        public static var listEmpty: String { tr("friend.list.empty") }
        public static func userIdPrefix(_ id: String) -> String {
            String(format: tr("friend.list.user_id_prefix"), id)
        }
        
        // Add Screen (C03)
        public static var addTitle: String { tr("friend.add.title") }
        public static var tabQR: String { tr("friend.add.tab_qr") }
        public static var tabText: String { tr("friend.add.tab_text") }
        public static var cameraSimulatorBtn: String { tr("friend.add.camera_simulator_btn") }
        public static var passcodeTitle: String { tr("friend.add.passcode_title") }
        public static var myInfoSection: String { tr("friend.add.my_info_section") }
        public static var userIdLabel: String { tr("friend.add.user_id_label") }
        public static var textInputSection: String { tr("friend.add.text_input_section") }
        public static var targetUserIdPlaceholder: String { tr("friend.add.target_user_id_placeholder") }
        public static var targetPasscodePlaceholder: String { tr("friend.add.target_passcode_placeholder") }
        public static var confirmAdditionBtn: String { tr("friend.add.confirm_addition_btn") }
        public static var successAlertTitle: String { tr("friend.add.success_alert_title") }
        public static func successAlertMsg(_ name: String) -> String {
            String(format: tr("friend.add.success_alert_msg"), name)
        }
        public static var confirmSheetTitle: String { tr("friend.add.confirm_sheet_title") }
        public static func confirmSheetMsg(_ name: String, _ id: String) -> String {
            String(format: tr("friend.add.confirm_sheet_msg"), name, id)
        }
    }
    
    // MARK: - Settings
    public enum Settings {
        public static var title: String { tr("settings.title") }
        public static var sectionProfile: String { tr("settings.section.profile") }
        public static var sectionTenant: String { tr("settings.section.tenant") }
        public static var sectionSecurity: String { tr("settings.section.security") }
        public static var sectionAbout: String { tr("settings.section.about") }
        public static var profileDisplayName: String { tr("settings.profile.display_name") }
        public static var profileUsername: String { tr("settings.profile.username") }
        public static var profileUsernamePlaceholder: String { tr("settings.profile.username_placeholder") }
        public static var profileUsernameInvalidFormat: String { tr("settings.profile.username_invalid_format") }
        public static var profileUsernameConfirmTitle: String { tr("settings.profile.username_confirm_title") }
        public static var profileUsernameConfirmMsg: String { tr("settings.profile.username_confirm_msg") }
        public static var profileUsernameConfirmButton: String { tr("settings.profile.username_confirm_button") }
        public static var profileUserId: String { tr("settings.profile.user_id") }
        public static var profileDefaultUser: String { tr("settings.profile.default_user") }
        public static var tenantName: String { tr("settings.tenant.name") }
        public static var tenantCode: String { tr("settings.tenant.code") }
        public static var tenantId: String { tr("settings.tenant.id") }
        public static var tenantUnconnected: String { tr("settings.tenant.unconnected") }
        public static var securityResetTitle: String { tr("settings.security.reset_title") }
        public static var securityResetConfirmTitle: String { tr("settings.security.reset_confirm_title") }
        public static var securityResetConfirmMsg: String { tr("settings.security.reset_confirm_msg") }
        public static var securityResetExecute: String { tr("settings.security.reset_execute") }
        public static var securityResetSuccessTitle: String { tr("settings.security.reset_success_title") }
        public static var securityResetSuccessMsg: String { tr("settings.security.reset_success_msg") }
        public static var recoveryTitle: String { tr("settings.recovery.title") }
        public static var recoveryDesc: String { tr("settings.recovery.desc") }
        public static var logout: String { tr("settings.logout") }
        public static var logoutConfirmTitle: String { tr("settings.logout.confirm_title") }
        public static var logoutConfirmMsg: String { tr("settings.logout.confirm_msg") }
        public static var aboutVersion: String { tr("settings.about.version") }
        public static var aboutEncryption: String { tr("settings.about.encryption") }
        
        // Profile Edit (B03)
        public static var editProfileTitle: String { tr("settings.profile.edit_title") }
        public static var editProfilePlaceholder: String { tr("settings.profile.edit_placeholder") }
        public static var editProfileEmptyError: String { tr("settings.profile.edit_empty_error") }
        public static var avatarChange: String { tr("settings.profile.avatar_change") }
        public static var avatarChoosePhoto: String { tr("settings.profile.avatar_choose_photo") }
        public static var avatarPresetTitle: String { tr("settings.profile.avatar_preset_title") }
        public static var avatarRemove: String { tr("settings.profile.avatar_remove") }
    }
    
    // MARK: - Errors
    public enum Error {
        public static var unknown: String { tr("error.unknown") }
        
        public enum Friend {
            public static var invalidFormat: String { tr("error.friend.invalid_format") }
            public static var userNotFound: String { tr("error.friend.user_not_found") }
            public static var passcodeExpired: String { tr("error.friend.passcode_expired") }
            public static var tenantMismatch: String { tr("error.friend.tenant_mismatch") }
            public static var selfAdd: String { tr("error.friend.self_add") }
        }
    }
    
    // MARK: - Toast Notification
    public enum Toast {
        public static var newMessage: String { tr("toast.new_message") }
    }

    
    // MARK: - Helper Lookup
    private static func tr(_ key: String) -> String {
        let localized = NSLocalizedString(key, comment: "")
        if localized == key {
            // Fallback from Bundle.main or custom lookup
            if let path = Bundle.main.path(forResource: "ja", ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle.localizedString(forKey: key, value: key, table: nil)
            }
        }
        return localized
    }
}
