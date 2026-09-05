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
        public static var recoveryRestoreButton: String { tr("auth.recovery.restore_button") }
        public static func recoveryWordCountError(count: Int) -> String { String(format: tr("auth.recovery.word_count_error"), count) }
        public static var recoveryInvalidPhrase: String { tr("auth.recovery.invalid_phrase") }
        public static var recoveryRestoredUserPrefix: String { tr("auth.recovery.restored_user_prefix") }
    }
    
    // MARK: - Tenant Selection
    public enum Tenant {
        public static var selectionTitle: String { tr("tenant.selection.title") }
        public static var header: String { tr("tenant.selection.header") }
        public static var subtitle: String { tr("tenant.selection.subtitle") }
        public static var tab2DCode: String { tr("tenant.tab.two_dimensional_code") }
        public static var tabURL: String { tr("tenant.tab.url") }
        public static var tabText: String { tr("tenant.tab.text") }
        public static var verifying: String { tr("tenant.verify.verifying") }
        public static var confirmBtn: String { tr("tenant.verify.confirm_btn") }
        public static var defaultBadge: String { tr("tenant.default_badge") }
        public static var inputLabel: String { tr("tenant.input.label") }
        public static var urlLabel: String { tr("tenant.input.url_label") }
        public static var urlPlaceholder: String { tr("tenant.input.url_placeholder") }
        public static var verifyBtn: String { tr("tenant.verify.btn") }
        public static var cameraInstruction: String { tr("tenant.camera.instruction") }
    }
    
    // MARK: - Tabs
    public enum Tab {
        public static var home: String { tr("tab.home") }
        public static var friends: String { tr("tab.friends") }
        public static var groups: String { tr("tab.groups") }
    }
    
    // MARK: - Home
    public enum Home {
        public static var quickActionTitle: String { tr("home.quick_action.title") }
        public static var quickActionAddFriend: String { tr("home.quick_action.add_friend") }
        public static var notificationTitle: String { tr("home.notification.title") }
        public static var notificationEmpty: String { tr("home.notification.empty") }
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
        
        // Roles & Actions
        public static var roleOwner: String { tr("group.role.owner") }
        public static var roleAdmin: String { tr("group.role.admin") }
        public static var roleMember: String { tr("group.role.member") }
        public static var claimOwner: String { tr("group.action.claim_owner") }
        public static var claimOwnerConfirm: String { tr("group.action.claim_owner_confirm") }
        public static var assignAdmin: String { tr("group.action.assign_admin") }
        public static func assignAdminConfirm(_ name: String) -> String {
            String(format: tr("group.action.assign_admin_confirm"), name)
        }
        public static var removeMember: String { tr("group.action.remove_member") }
        public static func removeMemberConfirm(_ name: String) -> String {
            String(format: tr("group.action.remove_member_confirm"), name)
        }
        public static var leaveGroup: String { tr("group.action.leave_group") }
        public static var leaveGroupConfirm: String { tr("group.action.leave_group_confirm") }
        public static var cannotLeaveOwner: String { tr("group.action.cannot_leave_owner") }
        public static var editTitle: String { tr("group.action.edit_title") }
        public static var editTitlePrompt: String { tr("group.action.edit_title_prompt") }
        public static var addMemberAction: String { tr("group.action.add_member") }
        public static var addMemberTitle: String { tr("group.add_member.title") }
        public static var addMemberSubmitBtn: String { tr("group.add_member.submit_btn") }
        public static var addMemberNoCandidates: String { tr("group.add_member.no_candidates") }
        public static func addMemberSelectCount(_ count: Int) -> String {
            String(format: tr("group.add_member.select_count"), count)
        }
        public static var avatarChangeTitle: String { tr("group.avatar.change_title") }
        
        // Deletion (Single Confirmation with Important Warning)
        public static var deleteButton: String { tr("group.delete.button") }
        public static func deleteConfirmTitle(_ title: String) -> String {
            String(format: tr("group.delete.confirm_title"), title)
        }
        public static var deleteConfirmMessage: String { tr("group.delete.confirm_message") }
        public static var deleteConfirmAction: String { tr("group.delete.confirm_action") }
    }
    
    // MARK: - Chats
    public enum Chat {
        public static var listTitle: String { tr("chat.list.title") }
        public static var listEmpty: String { tr("chat.list.empty") }
        public static var inputPlaceholder: String { tr("chat.detail.input_placeholder") }
        public static var send: String { tr("chat.detail.send") }
        public static var newMessagesBadge: String { tr("chat.detail.new_messages_badge") }
        public static var scrollToLatest: String { tr("chat.detail.scroll_to_latest") }
        public static var detailEmpty: String { tr("chat.detail.empty") }
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
        public static var tab2DCode: String { tr("friend.add.tab_two_dimensional_code") }
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
        
        // Edit Friend Display Name
        public static var editNameAction: String { tr("friend.edit_name.action") }
        public static var editNameTitle: String { tr("friend.edit_name.title") }
        public static var editNameMessage: String { tr("friend.edit_name.message") }
        public static var editNamePlaceholder: String { tr("friend.edit_name.placeholder") }
        public static var editNameSave: String { tr("friend.edit_name.save") }
        public static var editNameSuccess: String { tr("friend.edit_name.success") }
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
        public static var recoveryRegenerateBtn: String { tr("settings.recovery.regenerate_btn") }
        public static var recoveryRegenerateTitle: String { tr("settings.recovery.regenerate_title") }
        public static var recoveryRegeneratePrompt: String { tr("settings.recovery.regenerate_prompt") }
        public static var recoveryRegenerateAction: String { tr("settings.recovery.regenerate_action") }
        public static var recoveryRegenerateSuccess: String { tr("settings.recovery.regenerate_success") }
        public static var recoveryCopyButton: String { tr("settings.recovery.copy_button") }
        public static var recoveryCopied: String { tr("settings.recovery.copied") }
        public static var recoveryNotFound: String { tr("settings.recovery.not_found") }
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
        
        public enum Recovery {
            public static var dataNotFound: String { tr("error.recovery.data_not_found") }
            public static var decryptionFailed: String { tr("error.recovery.decryption_failed") }
            public static var tenantNotConfigured: String { tr("error.recovery.tenant_not_configured") }
        }
        
        public enum Tenant {
            public static var invalidFormat: String { tr("error.tenant.invalid_format") }
            public static var fetchFailed: String { tr("error.tenant.fetch_failed") }
            public static func verificationFailed(_ reason: String) -> String {
                String(format: tr("error.tenant.verification_failed"), reason)
            }
        }
        
        public enum User {
            public static var notFound: String { tr("error.user.not_found") }
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
