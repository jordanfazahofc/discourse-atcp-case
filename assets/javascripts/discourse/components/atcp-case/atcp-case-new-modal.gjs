import Component from "@glimmer/component";
import { cached, tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import Form from "discourse/components/form";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { eq, not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import { i18n } from "discourse-i18n";
import { exceedsAttachmentLimit } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-attachments";
import { normalizeCaseErrors } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-errors";
import { caseSeverityKey } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-list-params";
import AtcpCaseProductMultiChooser from "./atcp-case-product-multi-chooser";
import AtcpCaseDetailAttachmentsEditor from "./detail/attachments-editor";

const FORM_FIELDS = new Set([
  "title",
  "case_type",
  "severity",
  "source",
  "symptom",
  "product_ids",
  "assignee_id",
]);

const SERVER_FIELD_LABELS = {
  bios_version: "bios_version",
  frequency: "frequency",
  reproducibility: "reproducibility",
};

function humanizeField(field) {
  const label = String(field).replaceAll("_", " ");
  return label.charAt(0).toUpperCase() + label.slice(1);
}

export default class AtcpCaseNewModal extends Component {
  @service router;
  @service atcpCaseReturnUrl;

  @tracked formApi;
  @tracked isSubmitting = false;
  @tracked serverErrors = [];
  @tracked selectedProducts = [];
  @tracked uploadIdsErrors = [];
  @tracked
  attachmentsState = {
    uploadIds: [],
    hasUploadsInProgress: false,
    totalAttachmentCount: 0,
  };

  @cached
  get initialData() {
    return {
      title: "",
      case_type: null,
      severity: "Medium",
      source: "",
      product_ids: [],
      symptom: "",
      assignee_id: null,
    };
  }

  get caseTypeOptions() {
    return (this.args.model?.formOptions?.case_types || []).map((caseType) => ({
      value: caseType,
      label: caseType,
    }));
  }

  get severityOptions() {
    return (this.args.model?.formOptions?.severities || []).map((severity) => ({
      value: severity,
      label: i18n(`atcp_case.cases.severities.${caseSeverityKey(severity)}`),
    }));
  }

  get picGroups() {
    return (this.args.model?.picGroups?.groups || [])
      .map((group) => ({
        name: group.name,
        users: (group.users || []).map((user) => ({
          id: String(user.id),
          label: user.name || user.username,
        })),
      }))
      .filter((group) => group.users.length > 0);
  }

  get uploadOptions() {
    return this.args.model?.formOptions?.upload;
  }

  get attachmentsUploadId() {
    return "atcp-case-new";
  }

  get submitDisabled() {
    return (
      this.isSubmitting ||
      this.attachmentsState.hasUploadsInProgress ||
      exceedsAttachmentLimit({ uploadIds: this.attachmentsState.uploadIds })
    );
  }

  @action
  registerApi(api) {
    this.formApi = api;
  }

  @action
  submitForm() {
    this.formApi?.submit();
  }

  @action
  cancel() {
    this.args.closeModal();
  }

  @action
  validateProducts(name, value, { addError }) {
    if (!value || value.length === 0) {
      addError(name, {
        title: i18n("atcp_case.cases.new.fields.product_ids"),
        message: i18n("atcp_case.cases.new.validation.products_required"),
      });
    }
  }

  @action
  async changeProducts(field, values, items) {
    this.selectedProducts = items || [];
    await field.set(values || []);
  }

  @action
  attachmentsChanged(state) {
    this.attachmentsState = state;
    this.uploadIdsErrors = [];
  }

  @action
  updateNativeField(field, event) {
    field.set(event.target.value || null);
  }

  @action
  async onSubmit(data) {
    if (this.submitDisabled) {
      return;
    }

    this.formApi?.removeErrors();
    this.serverErrors = [];
    this.uploadIdsErrors = [];
    this.isSubmitting = true;

    try {
      const response = await ajax("/atcp/cases.json", {
        type: "POST",
        data: this.buildPayload(data),
      });

      this.args.closeModal();
      this.atcpCaseReturnUrl.remember(this.router.currentURL);
      this.router.transitionTo("atcp-cases.show", response.case.id);
    } catch (error) {
      if (error?.jqXHR?.status === 422) {
        this.applyServerErrors(error.jqXHR.responseJSON);
      } else {
        popupAjaxError(error);
      }
    } finally {
      this.isSubmitting = false;
    }
  }

  buildPayload(data) {
    const payload = {
      title: data.title,
      case_type: data.case_type,
      severity: data.severity,
      source: data.source,
      symptom: data.symptom,
      product_ids: data.product_ids || [],
    };

    if (data.assignee_id) {
      payload.assignee_id = data.assignee_id;
    }

    if (this.attachmentsState.uploadIds.length) {
      payload.upload_ids = [...this.attachmentsState.uploadIds];
    }

    return payload;
  }

  applyServerErrors(payload) {
    const { fieldErrors, baseErrors } = normalizeCaseErrors(payload);
    const messages = [...baseErrors];

    Object.entries(fieldErrors).forEach(([field, fieldMessages]) => {
      if (field === "upload_ids") {
        this.uploadIdsErrors = [...fieldMessages];
        return;
      }

      if (FORM_FIELDS.has(field)) {
        const title = this.fieldLabel(field);
        fieldMessages.forEach((message) => {
          this.formApi?.addError(field, { title, message });
        });
      } else {
        fieldMessages.forEach((message) => {
          messages.push(`${this.fieldLabel(field)}: ${message}`);
        });
      }
    });

    this.serverErrors = messages;
  }

  fieldLabel(field) {
    if (FORM_FIELDS.has(field)) {
      return i18n(`atcp_case.cases.new.fields.${field}`);
    }

    const key = SERVER_FIELD_LABELS[field];
    return key
      ? i18n(`atcp_case.cases.new.server_fields.${key}`)
      : humanizeField(field);
  }

  <template>
    <DModal
      @inline={{@inline}}
      @title={{i18n "atcp_case.cases.new.title"}}
      @closeModal={{@closeModal}}
      class="atcp-case-new-modal"
    >
      <:body>
        <p class="atcp-case-new-modal__description">
          {{i18n "atcp_case.cases.new.description"}}
        </p>

        {{#if this.serverErrors.length}}
          <div
            class="alert alert-error atcp-case-new-modal__errors"
            role="alert"
          >
            <p class="atcp-case-new-modal__errors-title">
              {{i18n "atcp_case.cases.new.errors_title"}}
            </p>
            <ul class="atcp-case-new-modal__errors-list">
              {{#each this.serverErrors as |message|}}
                <li>{{message}}</li>
              {{/each}}
            </ul>
          </div>
        {{/if}}

        <Form
          @data={{this.initialData}}
          @onSubmit={{this.onSubmit}}
          @onRegisterApi={{this.registerApi}}
          as |form|
        >
          <form.Field
            @name="title"
            @title={{i18n "atcp_case.cases.new.fields.title"}}
            @type="input"
            @format="full"
            @validation="required:trim|length:0,255"
            @placeholder={{i18n "atcp_case.cases.new.placeholders.title"}}
            as |field|
          >
            <field.Control autofocus maxlength="255" autocomplete="off" />
          </form.Field>

          <form.Row as |row|>
            <row.Col @size={{4}}>
              <form.Field
                @name="case_type"
                @title={{i18n "atcp_case.cases.new.fields.case_type"}}
                @type="select"
                @validation="required"
                as |field|
              >
                <field.Control
                  @nonePlaceholder={{i18n
                    "atcp_case.cases.new.placeholders.case_type"
                  }}
                  as |select|
                >
                  {{#each this.caseTypeOptions as |option|}}
                    <select.Option @value={{option.value}}>
                      {{option.label}}
                    </select.Option>
                  {{/each}}
                </field.Control>
              </form.Field>
            </row.Col>

            <row.Col @size={{4}}>
              <form.Field
                @name="severity"
                @title={{i18n "atcp_case.cases.new.fields.severity"}}
                @type="select"
                @validation="required"
                as |field|
              >
                <field.Control as |select|>
                  {{#each this.severityOptions as |option|}}
                    <select.Option @value={{option.value}}>
                      {{option.label}}
                    </select.Option>
                  {{/each}}
                </field.Control>
              </form.Field>
            </row.Col>

            <row.Col @size={{4}}>
              <form.Field
                @name="source"
                @title={{i18n "atcp_case.cases.new.fields.source"}}
                @type="input"
                @validation="required:trim|length:0,255"
                @placeholder={{i18n "atcp_case.cases.new.placeholders.source"}}
                as |field|
              >
                <field.Control maxlength="255" autocomplete="off" />
              </form.Field>
            </row.Col>
          </form.Row>

          <form.Field
            @name="product_ids"
            @title={{i18n "atcp_case.cases.new.fields.product_ids"}}
            @type="custom"
            @format="full"
            @showOptional={{false}}
            @validate={{this.validateProducts}}
            as |field|
          >
            <field.Control>
              <AtcpCaseProductMultiChooser
                class="atcp-case-product-chooser"
                @value={{field.value}}
                @content={{this.selectedProducts}}
                @onChange={{fn this.changeProducts field}}
                @options={{hash
                  allowAny=false
                  filterable=true
                  filterPlaceholder="atcp_case.cases.new.placeholders.product"
                  useHeaderFilter=true
                }}
              />
            </field.Control>
          </form.Field>

          <form.Field
            @name="symptom"
            @title={{i18n "atcp_case.cases.new.fields.symptom"}}
            @type="textarea"
            @format="full"
            @validation="required:trim"
            @placeholder={{i18n "atcp_case.cases.new.placeholders.symptom"}}
            as |field|
          >
            <field.Control rows="5" />
          </form.Field>

          <AtcpCaseDetailAttachmentsEditor
            @classPrefix="atcp-case-new-modal"
            @uploadId={{this.attachmentsUploadId}}
            @uploadOptions={{this.uploadOptions}}
            @titleKey="atcp_case.cases.new.fields.attachments"
            @hintKey="atcp_case.cases.new.attachments_hint"
            @uploadWaitMessageKey="atcp_case.cases.new.upload_wait"
            @uploadErrors={{this.uploadIdsErrors}}
            @onChange={{this.attachmentsChanged}}
          />

          <form.Section
            @title={{i18n "atcp_case.cases.new.optional"}}
            class="atcp-case-new-modal__optional"
          >
            <form.Row as |row|>
              <row.Col @size={{4}}>
                <form.Field
                  @name="assignee_id"
                  @title={{i18n "atcp_case.cases.new.fields.assignee_id"}}
                  @type="custom"
                  @showOptional={{false}}
                  as |field|
                >
                  <field.Control>
                    <select
                      id={{field.id}}
                      name={{field.name}}
                      class="atcp-case-new-modal__select"
                      value={{field.value}}
                      aria-describedby={{field.describedBy}}
                      aria-invalid={{if field.error "true"}}
                      {{on "change" (fn this.updateNativeField field)}}
                    >
                      <option value="" selected={{not field.value}}>
                        {{i18n "atcp_case.cases.new.options.unassigned"}}
                      </option>
                      {{#each this.picGroups as |group|}}
                        <optgroup label={{group.name}}>
                          {{#each group.users as |user|}}
                            <option
                              value={{user.id}}
                              selected={{eq field.value user.id}}
                            >
                              {{user.label}}
                            </option>
                          {{/each}}
                        </optgroup>
                      {{/each}}
                    </select>
                  </field.Control>
                </form.Field>
              </row.Col>
            </form.Row>
          </form.Section>
        </Form>
      </:body>

      <:footer>
        <DButton
          @translatedLabel={{i18n "atcp_case.cases.new.cancel"}}
          class="btn-default atcp-case-new-modal__cancel"
          @action={{this.cancel}}
        />
        <DButton
          @translatedLabel={{i18n "atcp_case.cases.new.submit"}}
          class="btn-primary atcp-case-new-modal__submit"
          @action={{this.submitForm}}
          @disabled={{this.submitDisabled}}
          @isLoading={{this.isSubmitting}}
        />
      </:footer>
    </DModal>
  </template>
}
