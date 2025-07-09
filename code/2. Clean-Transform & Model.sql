-- Xem tổng số giá trị null ở mỗi cột
select 
    count(case when Title        is null then 1 end) as Title_Null_Count,
	count(case when Year         is null then 1 end) as Year_Null_Count,
	count(case when Duration     is null then 1 end) as Duration_Null_Count,
	count(case when MPAA         is null then 1 end) as MPAA_Null_Count,
	count(case when Genres       is null then 1 end) as Genres_Null_Count,
	count(case when IMDb_Rating  is null then 1 end) as IMDb_Rating_Null_Count,
    count(case when Director     is null then 1 end) as Director_Null_Count,
    count(case when Stars        is null then 1 end) as Stars_Null_Count,
    count(case when Plot_Summary is null then 1 end) as Plot_Summary_Null_Count,
	count(case when Votes		 is null then 1 end) as Votes_Null_Count
from Movies;

-- Tìm tất cả các dòng trong bảng Movies và lọc ra những dòng mà các cột Title, Director, Stars, Genres, hoặc Plot_Summary có khoảng trắng thừa (ở đầu hoặc cuối chuỗi).
select *
from Movies
where 
    Title        <> ltrim(rtrim(Title))    or
    Director     <> ltrim(rtrim(Director)) or
    Stars        <> ltrim(rtrim(Stars))    or
    Genres       <> ltrim(rtrim(Genres))   or
    Plot_Summary <> ltrim(rtrim(Plot_Summary));

-- Thủ tục xử lý tạo cột Duration_In_Minutes
create procedure AddDurationInMinutesColumn
as
begin
    -- Kiểm tra và thêm cột Duration_In_Minutes nếu chưa tồn tại
    if not exists (
        select * 
        from sys.columns 
        where Name      = N'Duration_In_Minutes' 
        and   Object_ID = OBJECT_ID(N'Movies')
    )
    begin
        alter table Movies add Duration_In_Minutes varchar(10);
    end
end;
exec AddDurationInMinutesColumn;

-- Thủ tục xử lý Duration_In_Minutes
create procedure UpdateDurationInMinutes
as
begin
    -- Cập nhật giá trị Duration_In_Minutes từ cột Duration
    update Movies
    set Duration_In_Minutes = 
        case 
            -- Format thời lượng '1h 45min' thành phút
            when Duration like '%h%' and Duration like '%min%' 
			then 
                cast((cast(left(Duration, charindex('h', Duration) - 1) as int) * 60 +
                cast(substring(Duration, charindex(' ', Duration) + 1, charindex('min', Duration) - 
				charindex(' ', Duration) - 1) as int)) as varchar(10))
            
            -- Format thời lượng chỉ chứa giờ '1h' thành phút
            when Duration like '%h%' 
			then
                cast(cast(left(Duration, charindex('h', Duration) - 1) as int) * 60 as varchar(10))
            
            -- Format thời lượng chỉ chứa phút '45min'
            when Duration like '%min%' 
			then
                cast(left(Duration, charindex('min', Duration) - 1) as varchar(10))
            
            -- Nếu không nhận dạng được định dạng
            else null
        end;
end;

-- Thủ tục xử lý các giá trị thiếu (NULL)
create procedure HandleMissingValues
as
begin
    -- Xử lý giá trị NULL trong nhiều cột cùng lúc
     UPDATE Movies
    SET Duration             = COALESCE(Duration, 'Unknown'),
        Duration_In_Minutes  = COALESCE(Duration_In_Minutes, 'Unknown'),
        MPAA                 = CASE 
                                    WHEN MPAA IS NULL 
                                        OR MPAA = 'Not Rated' 
                                        OR MPAA = 'Unknown' 
                                        OR MPAA = 'Unrated' 
                                    THEN 'Not Rated' 
                                    ELSE MPAA 
                               END,
        Director             = COALESCE(Director, 'Unknown'),
        Stars                = COALESCE(Stars, 'Unknown');
    -- Xóa các bản ghi có giá trị NULL cho cột Genres
    delete from Movies
    where Genres    is null;

    -- Xóa các bản ghi có giá trị NULL cho cột Plot_Summary
    delete from Movies
    where Plot_Summary is null;

	-- Xóa các bản ghi có giá trị NULL cho cột Title
	delete from Movies
	where Title     is null;

	-- Xóa các bản ghi có giá trị NULL cho cột Votes
	delete from Movies
	where Votes     is null;
end;

-- Gọi các thủ tục trong một thủ tục tổng hợp
create procedure PreprocessMoviesData
as
begin
    -- Gọi thủ tục cập nhật Duration_In_Minutes
    exec UpdateDurationInMinutes;

    -- Gọi thủ tục xử lý các giá trị thiếu
    exec HandleMissingValues;
end;

-- Gọi thủ tục tổng hợp
exec PreprocessMoviesData;

-- Thủ tục tạo bảng
CREATE PROCEDURE CreateTable
AS
BEGIN
    SET NOCOUNT ON;

    -- Tạo bảng MPAA:
    IF OBJECT_ID('MPAA', 'U') IS NOT NULL DROP TABLE MPAA;
    CREATE TABLE MPAA (
        MPAA_ID INT PRIMARY KEY IDENTITY(1,1),
        MPAA VARCHAR(10) UNIQUE
    );

    -- Tạo bảng Genres:
    IF OBJECT_ID('Genres', 'U') IS NOT NULL DROP TABLE Genres;
    CREATE TABLE Genres (
        Genre_ID INT PRIMARY KEY IDENTITY(1,1),
        Genres VARCHAR(50) UNIQUE
    );

    -- Tạo bảng Director:
    IF OBJECT_ID('Director', 'U') IS NOT NULL DROP TABLE Director;
    CREATE TABLE Director (
        Director_ID INT PRIMARY KEY IDENTITY(1,1),
        Director VARCHAR(255) UNIQUE
    );

    -- Tạo bảng Stars:
    IF OBJECT_ID('Stars', 'U') IS NOT NULL DROP TABLE Stars;
    CREATE TABLE Stars (
        Star_ID INT PRIMARY KEY IDENTITY(1,1),
        Stars VARCHAR(255) UNIQUE
    );

    -- Tạo bảng Films:
    IF OBJECT_ID('Films', 'U') IS NOT NULL DROP TABLE Films;
    CREATE TABLE Films (
        Films_ID INT PRIMARY KEY IDENTITY(1,1),
        MPAA_ID INT FOREIGN KEY REFERENCES MPAA(MPAA_ID),
        Director_ID INT FOREIGN KEY REFERENCES Director(Director_ID),
        Title VARCHAR(225),
        [Year] INT,
        Duration VARCHAR(20),
        IMDb_Rating FLOAT,
        Plot_Summary VARCHAR(MAX),
		Votes INT,
        Duration_In_Minutes VARCHAR(10)
    );

    -- Tạo bảng phụ để lưu mối quan hệ nhiều - nhiều giữa bảng Films và bảng Genres:
    IF OBJECT_ID('FilmsGenres', 'U') IS NOT NULL DROP TABLE FilmsGenres;
    CREATE TABLE FilmsGenres (
        FilmsGenres_ID INT PRIMARY KEY IDENTITY(1,1),
        Films_ID INT FOREIGN KEY REFERENCES Films(Films_ID),
        Genre_ID INT FOREIGN KEY REFERENCES Genres(Genre_ID)
    );

    -- Tạo bảng phụ để lưu mối quan hệ nhiều - nhiều giữa bảng Films và bảng Stars:
    IF OBJECT_ID('FilmsStars', 'U') IS NOT NULL DROP TABLE Stars_Films;
    CREATE TABLE FilmsStars (
        FilmsStars_ID INT PRIMARY KEY IDENTITY(1,1),
        Films_ID INT FOREIGN KEY REFERENCES Films(Films_ID),
        Star_ID INT FOREIGN KEY REFERENCES Stars(Star_ID)
    );
END;

exec Createtable;

-- Thủ tục chèn dữ liệu
CREATE PROCEDURE InsertData
AS
BEGIN
    SET NOCOUNT ON;

    -- Chèn vào bảng Genres
    INSERT INTO Genres (Genres)
    SELECT DISTINCT TRIM(value) AS Genre
    FROM Movies
    CROSS APPLY STRING_SPLIT(Genres, ',');

    -- Chèn vào bảng MPAA
    INSERT INTO MPAA (MPAA)
    SELECT DISTINCT MPAA
    FROM Movies;

    -- Chèn vào bảng Director
    INSERT INTO Director (Director)
    SELECT DISTINCT Director
    FROM Movies;

    -- Chèn vào bảng Stars
    INSERT INTO Stars (Stars)
    SELECT DISTINCT TRIM(value) AS Stars
    FROM Movies
    CROSS APPLY STRING_SPLIT(Stars, ',');

    -- Chèn vào bảng Films
    INSERT INTO Films (MPAA_ID, Director_ID, Title, [Year], Duration, IMDb_Rating, Plot_Summary, Votes, Duration_In_Minutes)
    SELECT
        m.MPAA_ID,
        d.Director_ID,
        mo.Title,
        mo.[Year],
        mo.Duration,
        mo.IMDb_Rating,
        mo.Plot_Summary,
		mo.Votes,
        mo.Duration_In_Minutes
    FROM Movies mo
    LEFT JOIN MPAA m ON mo.MPAA = m.MPAA
    LEFT JOIN Director d ON mo.Director = d.Director;


    -- Chèn vào bảng FilmsGenres
    INSERT INTO FilmsGenres (Genre_ID, Films_ID)
    SELECT 
        g.Genre_ID,
        f.Films_ID
    FROM Movies mo
    JOIN Films f ON mo.Title = f.Title
    CROSS APPLY STRING_SPLIT(mo.Genres, ',') AS splitGenres
    JOIN Genres g ON TRIM(splitGenres.value) = g.Genres;

    -- Chèn vào bảng FilmsStars (mối quan hệ n-n giữa Stars và Films)
    INSERT INTO FilmsStars (Star_ID, Films_ID)
    SELECT 
        s.Star_ID,
        f.Films_ID
    FROM Movies mo
    JOIN Films f ON mo.Title = f.Title
    CROSS APPLY STRING_SPLIT(mo.Stars, ',') AS splitStars
    JOIN Stars s ON TRIM(splitStars.value) = s.Stars;
END;


-- Execute the procedure
exec InsertData;

select * from Movies

