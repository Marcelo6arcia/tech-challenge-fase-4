package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestDemoFaultOptInAndAuthorization(t *testing.T) {
	t.Setenv("OTEL_SDK_DISABLED", "true")
	cases := []struct {
		name        string
		enabled     bool
		method, key string
		expected    int
	}{
		{"disabled", false, "POST", "test-master", 404},
		{"missing key", true, "POST", "", 403},
		{"incorrect key", true, "POST", "wrong", 403},
		{"wrong method", true, "GET", "test-master", 405},
		{"authorized", true, "POST", "test-master", 200},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			app := &App{MasterKey: "test-master", DemoFaultEnabled: tc.enabled}
			request := httptest.NewRequest(tc.method, "/admin/demo/fault", nil)
			if tc.key != "" {
				request.Header.Set("Authorization", "Bearer "+tc.key)
			}
			recorder := httptest.NewRecorder()
			app.routes().ServeHTTP(recorder, request)
			if recorder.Code != tc.expected {
				t.Fatalf("status=%d want=%d", recorder.Code, tc.expected)
			}
			if app.demoFault.Load() != (tc.expected == 200) {
				t.Fatal("unauthorized state change")
			}
		})
	}
}

func TestDemoFaultAffectsValidationButKeepsHealthAndResets(t *testing.T) {
	t.Setenv("OTEL_SDK_DISABLED", "true")
	app := &App{MasterKey: "test-master", DemoFaultEnabled: true}
	request := httptest.NewRequest("POST", "/admin/demo/fault", nil)
	request.Header.Set("Authorization", "Bearer test-master")
	app.routes().ServeHTTP(httptest.NewRecorder(), request)
	for path, expected := range map[string]int{"/validate": http.StatusServiceUnavailable, "/health": http.StatusOK} {
		recorder := httptest.NewRecorder()
		app.routes().ServeHTTP(recorder, httptest.NewRequest("GET", path, nil))
		if recorder.Code != expected {
			t.Fatalf("%s status=%d", path, recorder.Code)
		}
	}
	restarted := &App{MasterKey: "test-master", DemoFaultEnabled: true}
	if restarted.demoFault.Load() {
		t.Fatal("fault survived new process state")
	}
	recorder := httptest.NewRecorder()
	restarted.routes().ServeHTTP(recorder, httptest.NewRequest("GET", "/validate", nil))
	if recorder.Code != http.StatusUnauthorized {
		t.Fatal("fresh process remains faulted")
	}
}
