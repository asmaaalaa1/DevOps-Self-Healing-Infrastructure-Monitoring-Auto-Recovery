import pytest
from main import app, db, Patient
from signup import Signup, Search
from flask import url_for, template_rendered

@pytest.fixture
def client():
    app.config["TESTING"] = True
    app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///:memory:"
    app.config["WTF_CSRF_ENABLED"] = False  # Disable CSRF for testing
    
    with app.test_client() as client:
        with app.app_context():
            db.create_all()
        yield client

def test_main_page(client):
    response = client.get("/")
    assert response.status_code == 200
    assert b"Main Page" in response.data

def test_signup_get(client):
    response = client.get("/signup")
    assert response.status_code == 200
    assert b"Sign Up" in response.data

def test_signup_post_success(client):
    data = {
        "username": "testuser",
        "email": "test@example.com",
        "password": "testpass",
        "Re_password": "testpass",
        "Fname": "Test",
        "Lname": "User",
        "NID": "123456789",
        "BD": "2000-01-01",
        "submit": True
    }
    
    response = client.post("/signup", data=data, follow_redirects=True)
    assert response.status_code == 200
    assert b"This User is added" in response.data
    assert b"testuser" in response.data

def test_signup_post_duplicate_nid(client):
    # First registration
    test_signup_post_success(client)
    
    # Try duplicate NID
    data = {
        "username": "anotheruser",
        "email": "another@example.com",
        "password": "pass123",
        "Re_password": "pass123",
        "Fname": "Another",
        "Lname": "User",
        "NID": "123456789",
        "BD": "1990-01-01",
        "submit": True
    }
    
    response = client.post("/signup", data=data)
    assert response.status_code == 200
    assert b"This id is aready IN" in response.data

def test_search_found(client):
    test_signup_post_success(client)
    
    response = client.post("/search", data={
        "NID": "123456789"
    })
    assert response.status_code == 200
    assert b"testuser" in response.data
    assert b"test@example.com" in response.data

def test_search_not_found(client):
    response = client.post("/search", data={
        "NID": "000000000"
    })
    assert response.status_code == 200
    assert b"Cant Find a User" in response.data
