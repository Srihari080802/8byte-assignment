from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_create_and_list_books():
    # Create a new book
    response = client.post(
        "/books",
        data={
            "title": "Test Book",
            "author": "Test Author",
            "description": "Test Description"
        }
    )
    assert response.status_code == 200  # Redirect after creation

    # List books and check if the new book is present
    response = client.get("/books")
    assert response.status_code == 200
    assert "Test Book" in response.text
    assert "Test Author" in response.text
    assert "Test Description" in response.text