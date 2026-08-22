/* global axios */
import ApiClient from './ApiClient';

class ScoutAPI extends ApiClient {
  constructor() {
    super('scouts', { accountScoped: true });
  }

  // Inboxes
  getInboxes(scoutId) {
    return axios.get(`${this.url}/${scoutId}/scout_inboxes`);
  }

  attachInbox(scoutId, inboxId) {
    return axios.post(`${this.url}/${scoutId}/scout_inboxes`, {
      inbox_id: inboxId,
    });
  }

  detachInbox(scoutId, associationId) {
    return axios.delete(
      `${this.url}/${scoutId}/scout_inboxes/${associationId}`
    );
  }

  // Products
  getProducts(scoutId) {
    return axios.get(`${this.url}/${scoutId}/product_catalog_items`);
  }

  createProduct(scoutId, data) {
    return axios.post(`${this.url}/${scoutId}/product_catalog_items`, data);
  }

  updateProduct(scoutId, productId, data) {
    return axios.patch(
      `${this.url}/${scoutId}/product_catalog_items/${productId}`,
      data
    );
  }

  deleteProduct(scoutId, productId) {
    return axios.delete(
      `${this.url}/${scoutId}/product_catalog_items/${productId}`
    );
  }

  // Knowledge Sources
  getKnowledgeSources(scoutId) {
    return axios.get(`${this.url}/${scoutId}/knowledge_sources`);
  }

  createKnowledgeSource(scoutId, data) {
    const isFormData = data instanceof FormData;
    return axios.post(
      `${this.url}/${scoutId}/knowledge_sources`,
      data,
      isFormData ? { headers: { 'Content-Type': 'multipart/form-data' } } : {}
    );
  }

  updateKnowledgeSource(scoutId, sourceId, data) {
    return axios.patch(
      `${this.url}/${scoutId}/knowledge_sources/${sourceId}`,
      data
    );
  }

  reprocessKnowledgeSource(scoutId, sourceId) {
    return axios.patch(`${this.url}/${scoutId}/knowledge_sources/${sourceId}`, {
      reprocess: true,
    });
  }

  deleteKnowledgeSource(scoutId, sourceId) {
    return axios.delete(`${this.url}/${scoutId}/knowledge_sources/${sourceId}`);
  }

  // Tools (Account-scoped)
  getTools() {
    const accountUrl = this.url.replace(/\/scouts$/, '');
    return axios.get(`${accountUrl}/scout_tools`);
  }

  createTool(data) {
    const accountUrl = this.url.replace(/\/scouts$/, '');
    return axios.post(`${accountUrl}/scout_tools`, data);
  }

  updateTool(toolId, data) {
    const accountUrl = this.url.replace(/\/scouts$/, '');
    return axios.patch(`${accountUrl}/scout_tools/${toolId}`, data);
  }

  deleteTool(toolId) {
    const accountUrl = this.url.replace(/\/scouts$/, '');
    return axios.delete(`${accountUrl}/scout_tools/${toolId}`);
  }

  testTool(data) {
    const accountUrl = this.url.replace(/\/scouts$/, '');
    return axios.post(`${accountUrl}/scout_tools/test`, data);
  }

  // Account LLM Config (Admin Only)
  getAccountConfig() {
    const accountUrl = this.url.replace(/\/scouts$/, '');
    return axios.get(`${accountUrl}/scout_account_config`);
  }

  updateAccountConfig(data) {
    const accountUrl = this.url.replace(/\/scouts$/, '');
    return axios.patch(`${accountUrl}/scout_account_config`, {
      scout_account_config: data,
    });
  }

  // Playground
  sendPlaygroundMessage(scoutId, payload) {
    const body = typeof payload === 'string' ? { message: payload } : payload;
    return axios.post(`${this.url}/${scoutId}/playground_messages`, body);
  }
}

export default new ScoutAPI();
