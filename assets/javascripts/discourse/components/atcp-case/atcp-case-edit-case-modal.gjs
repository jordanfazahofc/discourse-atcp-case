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
import {
  buildEditCasePayload,
  editCaseInitialData,
  editCaseProductItems,
  orphanCaseProducts,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-edit-case";
import { normalizeCaseErrors } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-errors";
import { caseSeverityKey } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-list-params";
import AtcpCaseProductMultiChooser from "./atcp-case-product-multi-chooser";

const FORM_FIELDS = new Set([
  "title",
  "case_type",
  "severity",
  "source",
  "product_ids",
  "assignee_id",
]);

function humanizeField(field) {
  const label = String(field).replaceAll("_", " ");
  return label.charAt(0).toUpperCase() + label.slice(1);
}

export default class AtcpCaseEditCaseModal extends Component {
  @service dialog;
  @service router;

  @tracked draft;
  @tracked formApi;
  @tracked isSubmitting = false;
  @tracked serverErrors = [];
  @tracked productsTouched = false;
  @tracked selectedProducts;

  constructor(owner, args) {
    super(owner, args);

    this.draft = editCaseInitialData(args.model?.atcpCase);
    this.selectedProducts = editCaseProductItems(args.model?.atcpCase);
  }

  @cached
  get initialData() {
    return editCaseInitialData(this.args.model?.atcpCase);
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
    const groups = (this.args.model?.picGroups?.groups || [])
      .map((group) => ({
        name: group.name,
        users: (group.users || []).map((user) => ({
          id: String(user.id),
          label: user.name || user.username,
        })),
      }))
      .filter((group) => group.users.length > 0);

    const current = this.args.model?.atcpCase?.assignee;
    if (
      current?.id &&
      !groups.some((group) =>
        group.users.some((user) => user.id === String(current.id))
      )
    ) {
      groups.push({
        name: i18n("atcp_case.cases.detail.edit_case.current_pic_group"),
        users: [
          {
            id: String(current.id),
            label: current.name || current.username,
          },
        ],
      });
    }

    return groups;
  }

  get orphanProductNames() {
    return orphanCaseProducts(this.args.model?.atcpCase)
      .map((product) => product.name || "-")
      .join(", ");
  }

  get hasChanges() {
    return (
      Object.keys(
        buildEditCasePayload({
          atcpCase: this.args.model?.atcpCase,
          data: this.draft,
          productsTouched: this.productsTouched,
        })
      ).length > 0
    );
  }

  get submitDisabled() {
    return this.isSubmitting || !this.hasChanges;
  }

  @action
  registerApi(api) {
    this.formApi = api;
  }

  @action
  onSet(name, value) {
    this.draft = { ...this.draft, [name]: value };
    this.serverErrors = [];
    this.formApi?.removeError(name);
  }

  @action
  submitForm() {
    this.formApi?.submit();
  }

  @action
  validateProducts(name, value, { addError }) {
    if (this.productsTouched && (!value || value.length === 0)) {
      addError(name, {
        title: i18n("atcp_case.cases.new.fields.product_ids"),
        message: i18n("atcp_case.cases.new.validation.products_required"),
      });
    }
  }

  @action
  async changeProducts(field, values, items) {
    this.productsTouched = true;
    this.selectedProducts = items || [];
    this.draft = { ...this.draft, product_ids: values || [] };
    await field.set(values || []);
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

    const payload = buildEditCasePayload({
      atcpCase: this.args.model?.atcpCase,
      data,
      productsTouched: this.productsTouched,
    });

    if (!Object.keys(payload).length) {
      this.args.closeModal();
      return;
    }

    this.formApi?.removeErrors();
    this.serverErrors = [];
    this.isSubmitting = true;

    try {
      await ajax(`/atcp/cases/${this.args.model?.atcpCase?.id}.json`, {
        type: "PUT",
        data: payload,
      });

      this.args.closeModal();
      this.args.model?.onSaved?.();
    } catch (error) {
      const status = error?.jqXHR?.status;

      if (status === 403) {
        this.args.closeModal();
        this.args.model?.onNoLongerEditable?.();
      } else if (status === 422) {
        this.applyServerErrors(error.jqXHR.responseJSON);
        await this.router.refresh();
      } else {
        popupAjaxError(error);
      }
    } finally {
      this.isSubmitting = false;
    }
  }

  @action
  async cancel() {
    if (!this.hasChanges) {
      this.args.closeModal();
      return;
    }

    const discard = await this.dialog.confirm({
      message: i18n("atcp_case.cases.detail.edit_case.discard_confirmation"),
      confirmButtonLabel: "atcp_case.cases.detail.edit_case.discard",
      cancelButtonLabel: "atcp_case.cases.detail.edit_case.keep_editing",
    });

    if (discard) {
      this.args.closeModal();
    }
  }

  @action
  async beforeClose() {
    if (!this.hasChanges) {
      return true;
    }

    return this.dialog.confirm({
      message: i18n("atcp_case.cases.detail.edit_case.discard_confirmation"),
      confirmButtonLabel: "atcp_case.cases.detail.edit_case.discard",
      cancelButtonLabel: "atcp_case.cases.detail.edit_case.keep_editing",
    });
  }

  applyServerErrors(payload) {
    const { fieldErrors, baseErrors } = normalizeCaseErrors(payload);
    const messages = [...baseErrors];

    Object.entries(fieldErrors).forEach(([field, fieldMessages]) => {
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

    return humanizeField(field);
  }

  <template>
    <DModal
      @title={{i18n "atcp_case.cases.detail.edit_case.title"}}
      @closeModal={{@closeModal}}
      @beforeClose={{this.beforeClose}}
      class="atcp-case-edit-case-modal"
    >
      <:body>
        {{#if this.serverErrors.length}}
          <div
            class="alert alert-error atcp-case-edit-case-modal__errors"
            role="alert"
          >
            <p class="atcp-case-edit-case-modal__errors-title">
              {{i18n "atcp_case.cases.detail.edit_case.errors_title"}}
            </p>
            <ul class="atcp-case-edit-case-modal__errors-list">
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
          @onSet={{this.onSet}}
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

          {{#if this.orphanProductNames}}
            <p class="atcp-case-edit-case-modal__orphan-products">
              {{i18n
                "atcp_case.cases.detail.edit_case.orphan_products"
                products=this.orphanProductNames
              }}
            </p>
          {{/if}}

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
                class="atcp-case-edit-case-modal__select"
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
        </Form>
      </:body>

      <:footer>
        <DButton
          @translatedLabel={{i18n "atcp_case.cases.detail.edit_case.cancel"}}
          class="btn-default atcp-case-edit-case-modal__cancel"
          @action={{this.cancel}}
        />
        <DButton
          @translatedLabel={{i18n "atcp_case.cases.detail.edit_case.save"}}
          class="btn-primary atcp-case-edit-case-modal__submit"
          @action={{this.submitForm}}
          @disabled={{this.submitDisabled}}
          @isLoading={{this.isSubmitting}}
        />
      </:footer>
    </DModal>
  </template>
}
