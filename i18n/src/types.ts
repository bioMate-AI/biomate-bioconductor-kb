/**
 * TypeScript types for BioMate translation keys.
 * These are manually maintained to stay in sync with en/common.json.
 * For full type-safety in the frontend, import TranslationKeys and use as:
 *   t(key: TranslationKeys)
 */

export type TranslationKeys =
  // nav
  | 'nav.dashboard' | 'nav.workflows' | 'nav.projects' | 'nav.datasets'
  | 'nav.settings' | 'nav.help' | 'nav.logout' | 'nav.admin' | 'nav.billing'
  // actions
  | 'actions.run' | 'actions.cancel' | 'actions.submit' | 'actions.save'
  | 'actions.delete' | 'actions.edit' | 'actions.create' | 'actions.close'
  | 'actions.back' | 'actions.next' | 'actions.confirm' | 'actions.download'
  | 'actions.upload' | 'actions.search' | 'actions.filter' | 'actions.reset'
  | 'actions.retry' | 'actions.copy' | 'actions.view' | 'actions.refresh'
  | 'actions.continue' | 'actions.skip' | 'actions.add' | 'actions.remove'
  | 'actions.apply' | 'actions.export' | 'actions.import'
  // workflow.status
  | 'workflow.status.running' | 'workflow.status.completed' | 'workflow.status.failed'
  | 'workflow.status.queued' | 'workflow.status.cancelled' | 'workflow.status.pending'
  | 'workflow.status.unknown'
  // workflow.labels
  | 'workflow.labels.workflow' | 'workflow.labels.run' | 'workflow.labels.parameters'
  | 'workflow.labels.results' | 'workflow.labels.logs' | 'workflow.labels.findings'
  | 'workflow.labels.methods' | 'workflow.labels.phase' | 'workflow.labels.step'
  | 'workflow.labels.input' | 'workflow.labels.output' | 'workflow.labels.duration'
  | 'workflow.labels.started' | 'workflow.labels.finished'
  // workflow.actions
  | 'workflow.actions.run_workflow' | 'workflow.actions.confirm_and_run'
  | 'workflow.actions.view_results' | 'workflow.actions.download_results'
  | 'workflow.actions.view_logs' | 'workflow.actions.override_params'
  | 'workflow.actions.run_step' | 'workflow.actions.pause_after'
  | 'workflow.actions.adjust_via_chat'
  // workflow.messages
  | 'workflow.messages.starting' | 'workflow.messages.running_phase'
  | 'workflow.messages.completed_successfully' | 'workflow.messages.failed_with_error'
  | 'workflow.messages.no_results_yet' | 'workflow.messages.fetching_results'
  // chat
  | 'chat.placeholder' | 'chat.send' | 'chat.new_chat' | 'chat.chat_history'
  | 'chat.no_history' | 'chat.thinking' | 'chat.generating'
  | 'chat.copy_message' | 'chat.regenerate' | 'chat.attach_file'
  // projects
  | 'projects.create_project' | 'projects.project_name' | 'projects.project_description'
  | 'projects.name_placeholder' | 'projects.description_placeholder'
  | 'projects.no_projects' | 'projects.create_first' | 'projects.last_updated'
  | 'projects.members' | 'projects.category' | 'projects.select_category'
  // datasets
  | 'datasets.upload_dataset' | 'datasets.dataset_name' | 'datasets.file_type'
  | 'datasets.file_size' | 'datasets.no_datasets' | 'datasets.drag_drop'
  | 'datasets.browse_files' | 'datasets.uploading' | 'datasets.upload_complete'
  // auth
  | 'auth.sign_in' | 'auth.sign_up' | 'auth.sign_out' | 'auth.email' | 'auth.password'
  | 'auth.forgot_password' | 'auth.remember_me' | 'auth.already_have_account'
  | 'auth.no_account' | 'auth.create_account'
  | 'auth.email_placeholder' | 'auth.password_placeholder'
  // settings
  | 'settings.title' | 'settings.language' | 'settings.select_language'
  | 'settings.theme' | 'settings.light' | 'settings.dark' | 'settings.system'
  | 'settings.display_name' | 'settings.email' | 'settings.role'
  | 'settings.save_settings' | 'settings.settings_saved'
  | 'settings.api_keys' | 'settings.notifications'
  // errors
  | 'errors.generic' | 'errors.network' | 'errors.not_found' | 'errors.unauthorized'
  | 'errors.session_expired' | 'errors.file_too_large' | 'errors.invalid_format'
  | 'errors.required_field' | 'errors.workflow_failed' | 'errors.server_error'
  // common
  | 'common.loading' | 'common.no_data' | 'common.yes' | 'common.no' | 'common.ok'
  | 'common.or' | 'common.and' | 'common.of' | 'common.all' | 'common.none'
  | 'common.optional' | 'common.required' | 'common.beta' | 'common.new'
  | 'common.updated' | 'common.deprecated' | 'common.experimental'
  | 'common.learn_more' | 'common.see_all' | 'common.show_more' | 'common.show_less'
  | 'common.copied' | 'common.not_available'
  // dmta
  | 'dmta.campaign' | 'dmta.compounds' | 'dmta.assay_results' | 'dmta.propose_next'
  | 'dmta.upload_assay' | 'dmta.export_cro' | 'dmta.ranking' | 'dmta.score'
  | 'dmta.bayesian_optimizer' | 'dmta.lims_sync'
  // languages
  | 'languages.en' | 'languages.zh' | 'languages.ja' | 'languages.es';

export type SupportedLocale = 'en' | 'zh' | 'ja' | 'es';
