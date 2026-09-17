/* global axios */
import ApiClient from './ApiClient';

class ScoutOverviewReportsAPI extends ApiClient {
  constructor() {
    super('scout_overview_reports', { accountScoped: true });
  }

  get(accountId, { scoutId, range, timezoneOffset } = {}) {
    return axios.get(this.url, {
      params: {
        scout_id: scoutId,
        range,
        timezone_offset: timezoneOffset,
      },
    });
  }

  getConversations(
    accountId,
    { scoutId, range, timezoneOffset, status, page, perPage } = {}
  ) {
    return axios.get(`${this.url}/conversations`, {
      params: {
        scout_id: scoutId,
        range,
        timezone_offset: timezoneOffset,
        status,
        page,
        per_page: perPage,
      },
    });
  }
}

export default new ScoutOverviewReportsAPI();
