import { getters } from '../../integrations';

describe('#getters', () => {
  it('getAppIntegrations', () => {
    const state = {
      records: [
        {
          id: 'dyte',
          name: 'dyte',
          logo: 'test',
          enabled: true,
        },
        {
          id: 'dialogflow',
          name: 'test2',
          logo: 'test',
          enabled: true,
        },
      ],
    };
    expect(getters.getAppIntegrations(state)).toEqual([
      {
        id: 'dyte',
        name: 'dyte',
        logo: 'test',
        enabled: true,
      },
      {
        id: 'dialogflow',
        name: 'test2',
        logo: 'test',
        enabled: true,
      },
    ]);
  });

  it('getUIFlags', () => {
    const state = {
      uiFlags: {
        isFetching: true,
        isFetchingItem: false,
        isUpdating: false,
      },
    };
    expect(getters.getUIFlags(state)).toEqual({
      isFetching: true,
      isFetchingItem: false,
      isUpdating: false,
    });
  });

  describe('getEnabledErpIntegration', () => {
    it('returns ERP app record with enabled hook when an ERP integration is active', () => {
      const younusApp = {
        id: 'younus',
        name: 'Younus',
        category: 'erp',
        enabled: true,
        hooks: [{ id: 1, status: true }],
      };
      const state = {
        records: [
          {
            id: 'slack',
            name: 'Slack',
            category: 'communication',
            enabled: true,
          },
          younusApp,
        ],
      };
      expect(getters.getEnabledErpIntegration(state)).toEqual(younusApp);
    });

    it('returns undefined when no ERP integration exists', () => {
      const state = {
        records: [
          {
            id: 'slack',
            name: 'Slack',
            category: 'communication',
            enabled: true,
          },
        ],
      };
      expect(getters.getEnabledErpIntegration(state)).toBeUndefined();
    });

    it('returns undefined when ERP integration hook is disabled', () => {
      const state = {
        records: [
          {
            id: 'younus',
            name: 'Younus',
            category: 'erp',
            enabled: false,
            hooks: [{ id: 1, status: false }],
          },
        ],
      };
      expect(getters.getEnabledErpIntegration(state)).toBeUndefined();
    });
  });
});
