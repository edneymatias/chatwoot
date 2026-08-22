import scoutAPI from '../scout';
import ApiClient from '../ApiClient';

describe('#scoutAPI', () => {
  it('creates correct instance', () => {
    expect(scoutAPI).toBeInstanceOf(ApiClient);
    expect(scoutAPI).toHaveProperty('getTools');
    expect(scoutAPI).toHaveProperty('createTool');
    expect(scoutAPI).toHaveProperty('updateTool');
    expect(scoutAPI).toHaveProperty('deleteTool');
    expect(scoutAPI).toHaveProperty('testTool');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve({ data: { success: true } })),
      get: vi.fn(() => Promise.resolve({ data: [] })),
      patch: vi.fn(() => Promise.resolve({ data: {} })),
      delete: vi.fn(() => Promise.resolve({ data: {} })),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#testTool sends POST request to test endpoint', () => {
      const testData = {
        endpoint_url: 'https://api.example.com/orders/{{order_id}}',
        http_method: 'GET',
        payload: { order_id: 123 },
        response_template: 'Order {{ r.id }}',
      };
      scoutAPI.testTool(testData);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/scout_tools/test',
        testData
      );
    });
  });
});
