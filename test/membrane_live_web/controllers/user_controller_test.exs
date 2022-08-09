defmodule MembraneLiveWeb.UserControllerTest do
  use MembraneLiveWeb.ConnCase

  import MembraneLive.AccountsFixtures

  alias MembraneLive.Accounts.User

  @create_attrs %{
    email: "some email",
    name: "some name",
    picture: "some picture"
  }
  @update_attrs %{
    email: "some updated email",
    name: "some updated name",
    picture: "some updated picture"
  }
  @invalid_attrs %{email: nil, name: nil, picture: nil}

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all users", %{conn: conn} do
      conn = get(conn, Routes.user_path(conn, :index))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create user" do
    test "renders user when data is valid", %{conn: conn} do
      conn = post(conn, Routes.user_path(conn, :create), user: @create_attrs)
      assert %{"uuid" => uuid} = json_response(conn, 201)["data"]

      conn = get(conn, Routes.user_path(conn, :show, uuid))

      assert %{
               "uuid" => ^uuid,
               "email" => "some email",
               "name" => "some name",
               "picture" => "some picture"
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, Routes.user_path(conn, :create), user: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "update user" do
    setup [:create_user]

    test "renders user when data is valid", %{conn: conn, user: %User{uuid: uuid} = user} do
      conn = put(conn, Routes.user_path(conn, :update, user), user: @update_attrs)
      assert %{"uuid" => ^uuid} = json_response(conn, 200)["data"]

      conn = get(conn, Routes.user_path(conn, :show, uuid))

      assert %{
               "uuid" => ^uuid,
               "email" => "some updated email",
               "name" => "some updated name",
               "picture" => "some updated picture"
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn, user: user} do
      conn = put(conn, Routes.user_path(conn, :update, user), user: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete user" do
    setup [:create_user]

    test "deletes chosen user", %{conn: conn, user: user} do
      conn = delete(conn, Routes.user_path(conn, :delete, user))
      assert response(conn, 204)

      conn = get(conn, Routes.user_path(conn, :show, user))
      assert response(conn, 404)
    end
  end

  defp create_user(_user) do
    user = user_fixture()
    %{user: user}
  end
end
