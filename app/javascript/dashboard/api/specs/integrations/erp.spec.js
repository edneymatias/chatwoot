import ErpAPI from '../../integrations/erp';
import ApiClient from '../../ApiClient';

describe('#ErpAPI', () => {
  it('creates correct instance', () => {
    expect(ErpAPI).toBeInstanceOf(ApiClient);
    expect(ErpAPI).toHaveProperty('get');
  });

  describe('get', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      get: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('creates a valid request with contact_id parameter', () => {
      ErpAPI.get(123);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/integrations/erp/data',
        {
          params: { contact_id: 123 },
        }
      );
    });
  });
});
